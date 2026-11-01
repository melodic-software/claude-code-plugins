#!/bin/sh
# guardrails pre-push check: CLI flags, /plugin:skill references and cited
# repository paths in the lines the pushed commits add.
#
#   reference-verify.sh <remote> <url>   the pushed ranges, refs on stdin (git
#                                        runs it as pre-push)
#   reference-verify.sh --worktree       the uncommitted changes against HEAD,
#                                        untracked files included
#
# Runs the three verifiers that used to report after every Claude Code edit
# (cli-flag-verify, skill-reference-verify, stale-path-verify) once per changed
# .md, .sh, .bash, .ps1 or .psm1 file outside an evals/**/samples/ folder
# (recorded model output), through the plugin's run-guards.sh
# dispatcher, all installed beside this script as entry assets. Each file is
# handed over the way the edit row handed it: a file new to the range as a
# Write of its whole content, a changed file as an Edit whose new text is the
# lines the range adds, so a finding is always about an added line; a file
# renamed, or copied from a file the range also changes, counts as changed. The
# verifiers' own scope gates hold (skill references are judged only in a
# marketplace repository). It runs at pre-push, not pre-commit, because its
# cost is over the commit budget (check-placement convention, measured rows).
#
# The ranges come from the check lib: one per pushed ref, a new branch from its
# merge-base with the remote's default branch, a deletion skipped. A hook
# manager that keeps stdin from this script leaves the lib's fallback: the
# current branch against its upstream. Whichever way it came, a range's base
# then moves up to the nearest of the remote's tracking refs between it and
# the tip (nearest_pushed_base), so a new branch stacked on a pushed branch is
# judged only on what it adds to that branch. A range whose tip merged the default
# branch is narrowed to the lines the branch itself adds (narrow_to_branch).
# Each range is checked on its own, in
# that range's tip: the checkout when HEAD is the tip and the tree is clean,
# else a temporary detached worktree of the tip, removed afterwards.
#
# A finding prints as "<path>:<line>: <message>" on stderr, the line being the
# first judged line holding the text the finding names (see report), and exits
# 1. Missing jq follows the check-placement contract: checks.skipmissing, else
# fail for an agent and a notice for a person.
#
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
here="$(cd "$here" && pwd)"
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail

# A declined entry checks nothing, whichever path registered it: a lefthook
# remote runs this script from the fetched copy, where no installer removed it.
# The keys read as install.mjs reads them: the entry's key at git's precedence,
# unset falling back to the master key, a non-boolean value not declining.
declined="$(git config --type=bool --get checks.guardrails.reference-verify.declined 2>/dev/null)"
[[ $? -eq 1 ]] && declined="$(git config --type=bool --get checks.git-hooks.declined 2>/dev/null)"
[[ "$declined" == true ]] && exit 0

checks_init pre-push "$@" || exit 0
checks_require_tool jq "https://jqlang.org/download/"

# The dispatcher and the verifiers: beside an installed copy, else the
# plugin's own hooks/. cli-flag-verify finds its verifier under
# $CLAUDE_PLUGIN_ROOT/lib/verification/, so an installed copy gets a scratch
# root holding the two verifier assets.
if [[ -f "$here/run-guards.sh" ]]; then
  run_guards="$here/run-guards.sh"
  root="$CHECKS_TMP/root"
  mkdir -p "$root/lib/verification"
  for f in verify-cli-flag.sh cli-flag-cache.sh; do
    [[ -f "$here/$f" ]] && cp "$here/$f" "$root/lib/verification/$f"
  done
  chmod +x "$root/lib/verification/verify-cli-flag.sh" 2>/dev/null
else
  run_guards="$here/../hooks/run-guards.sh"
  root="$(cd "$here/.." && pwd)"
fi
[[ -f "$run_guards" ]] || exit 0

# The tip and base of the range being checked; both empty for --worktree.
# MAIN_BASE is the tip's merge-base with the remote's default branch when the
# range carries commits merged in from it (see narrow_to_branch), else empty.
TIP=""
BASE=""
MAIN_BASE=""

# is_new <path>: the range adds the file rather than changing it.
is_new() {
  if [[ "$CHECKS_MODE" == worktree ]]; then
    ! git ls-files --error-unmatch -- ":(literal)$1" >/dev/null 2>&1 ||
      ! git cat-file -e "HEAD:$1" 2>/dev/null
    return
  fi
  ! git cat-file -e "$BASE:$1" 2>/dev/null &&
    { [[ -z "$MAIN_BASE" ]] || ! git cat-file -e "$MAIN_BASE:$1" 2>/dev/null; }
}

# changed_lines: the lib's ranges, except that a file the range adds as a copy
# of a file it also changes (a doc moved with a stub left at its old path) gets
# the lines a copy-detecting diff adds to it, not the whole file: it is judged
# like a rename's destination. The lib's diff detects renames, not copies.
changed_lines() {
  local d s
  checks_changed_lines
  : >"$CHECKS_TMP/copies"
  while IFS= read -r -d '' _ && IFS= read -r -d '' _ && IFS= read -r -d '' d; do
    printf '%s\n' "$d" >>"$CHECKS_TMP/copies"
  done < <(checks_diff --name-status -C --diff-filter=C -z 2>/dev/null)
  [[ -s "$CHECKS_TMP/copies" ]] || return 0
  checks_diff -U0 --text -C --diff-filter=C --src-prefix=a/ --dst-prefix=b/ 2>/dev/null |
    awk '
      /^\+\+\+ / { path = substr($0, 5); sub(/\t$/, "", path); if (path ~ /^b\//) path = substr(path, 3); else path = ""; next }
      /^@@ / && path != "" {
        split($3, n, ",")
        start = substr(n[1], 2) + 0
        count = (n[2] == "") ? 1 : n[2] + 0
        if (count > 0) printf "%s\t%d\t%d\n", path, start, start + count - 1
      }' >"$CHECKS_TMP/ranges.copy"
  # A failed stage fails the hook and keeps the lib's ranges, which judge a
  # copy whole: short ranges would drop findings. A diff stopped by SIGPIPE
  # (141) means awk stopped first, and awk reports.
  local -a st=("${PIPESTATUS[@]}")
  if ((st[0] != 0 && st[0] != 141)); then
    checks_tool_failed git "${st[0]}" 'listing the lines a copy adds'
    return 1
  fi
  if ((st[1] != 0)); then
    checks_tool_failed awk "${st[1]}" 'listing the lines a copy adds'
    return 1
  fi
  # A copy keeps its place in the table only when the lib listed it (a binary
  # file it dropped stays out); a copy that adds no line keeps no range.
  awk -F '\t' -v OFS='\t' '
    FILENAME == ARGV[1] { copy[$0] = 1; next }
    FILENAME == ARGV[2] { add[$1] = add[$1] $0 "\n"; next }
    !($1 in copy) { print; next }
    !($1 in done) { done[$1] = 1; printf "%s", add[$1] }' \
    "$CHECKS_TMP/copies" "$CHECKS_TMP/ranges.copy" "$CHECKS_TMP/ranges" >"$CHECKS_TMP/ranges.new"
  s=$?
  if ((s != 0)); then
    checks_tool_failed awk "$s" 'merging the lines a copy adds into the changed lines'
    return 1
  fi
  mv "$CHECKS_TMP/ranges.new" "$CHECKS_TMP/ranges"
}

# narrow_to_branch: a range whose tip merged the default branch since the last
# push holds the lines that merge brought in, which the branch did not write.
# Keep only the lines added both since the last push and against the tip's
# merge-base with the default branch, so a check never judges more than the
# plain range.
narrow_to_branch() {
  [[ -n "$MAIN_BASE" ]] || return 0
  mv "$CHECKS_TMP/ranges" "$CHECKS_TMP/ranges.push"
  printf '%s %s\n' "$MAIN_BASE" "$TIP" >"$CHECKS_TMP/push-ranges"
  changed_lines
  mv "$CHECKS_TMP/ranges" "$CHECKS_TMP/ranges.main"
  printf '%s %s\n' "$BASE" "$TIP" >"$CHECKS_TMP/push-ranges"
  awk -F '\t' -v OFS='\t' '
    NR == FNR { n++; p[n] = $1; s[n] = $2 + 0; e[n] = $3 + 0; next }
    { for (i = 1; i <= n; i++) if (p[i] == $1) {
        lo = ($2 + 0 > s[i]) ? $2 + 0 : s[i]; hi = ($3 + 0 < e[i]) ? $3 + 0 : e[i]
        if (lo <= hi) print $1, lo, hi } }' \
    "$CHECKS_TMP/ranges.main" "$CHECKS_TMP/ranges.push" >"$CHECKS_TMP/ranges.new"
  local s=$?
  # A failed awk fails the hook and keeps the plain range, never fewer lines.
  if ((s != 0)); then
    checks_tool_failed awk "$s" 'narrowing the changed lines to the branch'
    mv "$CHECKS_TMP/ranges.push" "$CHECKS_TMP/ranges"
    return 1
  fi
  mv "$CHECKS_TMP/ranges.new" "$CHECKS_TMP/ranges"
}

# nearest_pushed_base: moves BASE to the commit of a tracking ref of $remote
# that the tip holds and that holds BASE, the one fewest commits behind the tip.
# Those commits are on the remote already, so they are not judged again.
nearest_pushed_base() {
  local r n best="" min=0
  while IFS= read -r r; do
    [[ "$r" != "$BASE" ]] || continue
    n="$(git rev-list --count "$r..$TIP" 2>/dev/null)" || continue
    if [[ -z "$best" ]] || ((n < min)); then
      best="$r"
      min="$n"
    fi
  done < <(git for-each-ref --merged="$TIP" --contains="$BASE" --format='%(objectname)' "refs/remotes/$remote/" 2>/dev/null)
  [[ -z "$best" ]] || BASE="$best"
}

# main_base_for_range: sets MAIN_BASE for the current BASE..TIP, empty unless
# the default branch's merge-base is not already behind BASE.
main_base_for_range() {
  local head m
  MAIN_BASE=""
  head="$(checks_remote_head "$remote")"
  [[ -n "$head" ]] || return 0
  m="$(git merge-base "$TIP" "$head" 2>/dev/null)" || return 0
  [[ -n "$m" && "$m" != "$BASE" ]] || return 0
  git merge-base --is-ancestor "$m" "$BASE" 2>/dev/null && return 0
  MAIN_BASE="$m"
}

# added_lines <path>: the lines the range adds, in order.
added_lines() {
  awk -v want="$1" -v ranges="$CHECKS_TMP/ranges" '
    BEGIN { while ((getline l < ranges) > 0) { split(l, r, "\t"); if (r[1] == want) { n++; s[n] = r[2] + 0; e[n] = r[3] + 0 } } }
    { for (i = 1; i <= n; i++) if (NR >= s[i] && NR <= e[i]) { print; break } }'
}

first_line() {
  awk -v want="$1" -F '\t' '$1 == want { if (min == "" || $2 + 0 < min) min = $2 + 0 } END { print (min == "" ? 1 : min) }' \
    "$CHECKS_TMP/ranges"
}

# report <path> <whole>: the verifiers' report on stdin as "<path>:<line>: "
# rows. A detail line names a flag with its command ("faketool --bogus (not in
# ...)"), a path or a skill reference; it gets the first judged line of the tip's
# text ($CHECKS_TMP/file) holding that text, every line when <whole> is 1, else
# those the range adds. A heading gets its first detail's line; a line matching
# nothing, the file's first added line.
# The path travels in the environment: awk -v decodes a backslash escape, and
# the path is printed.
report() {
  REPORT_PATH="$1" awk -v whole="$2" -v first="$(first_line "$1")" \
    -v ranges="$CHECKS_TMP/ranges" -v file="$CHECKS_TMP/file" '
    function judged(i, k) {
      if (whole) return 1
      for (k = 1; k <= n; k++) if (i >= s[k] && i <= e[k]) return 1
      return 0
    }
    function locate(cmd, needle, i) {
      if (needle == "") return first
      for (i = 1; i <= lines; i++)
        if (index(src[i], needle) && (cmd == "" || index(src[i], cmd)) && judged(i)) return i
      return first
    }
    function row(at, msg) { printf "%s:%s: %s\n", want, at, msg }
    BEGIN {
      want = ENVIRON["REPORT_PATH"]
      while ((getline l < ranges) > 0) { split(l, r, "\t"); if (r[1] == want) { n++; s[n] = r[2] + 0; e[n] = r[3] + 0 } }
      while ((getline l < file) > 0) src[++lines] = l
    }
    /^[ \t]*$/ { next }
    !/^  / { if (head != "") row(first, head); head = $0; at = first; next }
    {
      d = substr($0, 3)
      if (d !~ /^\.\.\. and /) {
        cmd = ""; needle = d
        if ((p = index(d, " (not in ")) > 0) {
          needle = substr(d, 1, p - 1); cmd = needle
          sub(/ .*/, "", cmd); sub(/.* /, "", needle)
        } else if ((p = index(d, " (")) > 0) needle = substr(d, 1, p - 1)
        at = locate(cmd, needle)
      }
      if (head != "") { row(at, head); head = "" }
      row(at, $0)
    }
    END { if (head != "") row(first, head) }'
}

# verified_type <path>: an extension the verifiers read, outside an eval
# suite's samples/ folder. A sample is recorded model output: a flag, skill
# reference or path in it is data, not a claim the repository makes.
verified_type() {
  local f="$1"
  case "$f" in
    evals/samples/* | evals/*/samples/* | */evals/samples/* | */evals/*/samples/*) return 1 ;;
    *.md | *.sh | *.bash | *.ps1 | *.psm1) return 0 ;;
    *) return 1 ;;
  esac
}

out="$CHECKS_TMP/findings"
: >"$out"

# check_range: every file the current range (or the worktree) changes.
check_range() {
  local f ctx whole _
  local derived=$'\n' text="$CHECKS_TMP/text" payload="$CHECKS_TMP/payload"
  changed_lines
  narrow_to_branch
  # A rename's or a copy's destination is missing from the base but is no new
  # text: only the lines the range adds to it are judged.
  while IFS= read -r -d '' _ && IFS= read -r -d '' _ && IFS= read -r -d '' f; do
    derived+="$f"$'\n'
  done < <(checks_diff --name-status -C --diff-filter=RC -z 2>/dev/null)
  while IFS= read -r -d '' f; do
    verified_type "$f" || continue
    checks_regular_file --tip "$TIP" "$f" || continue
    # The text goes to jq as a file: an argument over the kernel's per-argument
    # limit (128 KiB on Linux) fails jq, and the file would go unjudged.
    # Git quotes a name holding a quote, a backslash or a control byte whatever
    # core.quotePath says, so the range table has no entry for it: such a file
    # is judged whole, as a new one is.
    checks_file_text --tip "$TIP" "$f" >"$CHECKS_TMP/file"
    whole=0
    if [[ "$f" == *[\"\\[:cntrl:]]* ]] || { [[ "$derived" != *$'\n'"$f"$'\n'* ]] && is_new "$f"; }; then
      whole=1
      jq -n --arg p "$PWD/$f" --rawfile c "$CHECKS_TMP/file" \
        '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}' >"$payload"
    else
      added_lines "$f" <"$CHECKS_TMP/file" >"$text"
      grep -q '[^[:space:]]' "$text" || continue
      jq -n --arg p "$PWD/$f" --rawfile c "$text" \
        '{hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: {file_path: $p, old_string: "", new_string: $c}}' >"$payload"
    fi
    # git exports GIT_DIR (a linked worktree's git dir) to its hooks; under it
    # `git -C <dir> rev-parse --show-toplevel` answers <dir>, so the verifiers
    # would take the file's own folder for the repository root. They find the
    # repository from the file, as an edit hook does.
    ctx="$(
      unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY \
        GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM
      CLAUDE_PLUGIN_ROOT="$root" checks_bash_run "$run_guards" cli-flag-verify.sh skill-reference-verify.sh stale-path-verify.sh <"$payload" 2>/dev/null |
        jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
    )"
    [[ -n "$ctx" ]] || continue
    report "$f" "$whole" <<<"$ctx" >>"$out"
  done < <(checks_files)
}

# tip_is_checkout: the checkout is the tip's tree (HEAD is $TIP, nothing changed
# or untracked), so the verifiers can read it directly.
tip_is_checkout() {
  [[ "$TIP" == "$(git rev-parse --verify --quiet HEAD 2>/dev/null)" && -z "$(git status --porcelain 2>/dev/null)" ]]
}

if [[ "$CHECKS_MODE" == worktree ]]; then
  check_range
else
  # The lib's diff helpers read $CHECKS_TMP/push-ranges; narrow it to one range
  # at a time so each file's text and added lines come from that range's tip.
  top="$PWD"
  tip_tree="$CHECKS_TMP/tip"
  mkdir -p "$CHECKS_TMP/no-hooks"
  # The lib's EXIT trap, then the prune: a lib tool failure still fails the hook.
  # shellcheck disable=SC2064 # expand now: the path is fixed here
  trap "checks_finish \$?; s=\$?; git -C '$top' worktree prune 2>/dev/null; ((s == 0)) || exit 1" EXIT
  mv "$CHECKS_TMP/push-ranges" "$CHECKS_TMP/all-ranges"
  remote="${CHECKS_ARGS%% *}"
  [[ -n "$remote" ]] || remote=origin
  while read -r BASE TIP <&3; do
    nearest_pushed_base
    printf '%s %s\n' "$BASE" "$TIP" >"$CHECKS_TMP/push-ranges"
    main_base_for_range
    if tip_is_checkout; then
      check_range
      continue
    fi
    # The verifiers read the tree around a file (cited paths, the plugins
    # tree, an edited file's other lines), so they run in a detached checkout
    # of the tip. An empty hooks path keeps post-checkout hooks from firing.
    if ! git -c core.hooksPath="$CHECKS_TMP/no-hooks" worktree add -q --detach "$tip_tree" "$TIP" >/dev/null 2>&1; then
      printf 'NOTICE: could not check out %s, so it was not checked.\n' "$TIP" >&2
      continue
    fi
    cd "$tip_tree" && check_range
    cd "$top" || exit 1
    git worktree remove --force "$tip_tree" >/dev/null 2>&1
    git worktree prune 2>/dev/null
  done 3<"$CHECKS_TMP/all-ranges"
fi

[[ -s "$out" ]] || exit 0
cat "$out" >&2
printf 'guardrails: correct each flag, skill reference or path above, commit the fix, then push again.\n' >&2
if grep -q ': cli-flag-verify: ' "$out"; then
  printf '%s\n' \
    'guardrails: a cli-flag finding is unverified, not proven wrong. When the flag is right, run /guardrails:setup to stop this' \
    'entry in this clone: it declines it (install.mjs decline --entry reference-verify) and removes its registration.' >&2
fi
printf '%s\n' 'guardrails: git -c checks.skipmissing=jq skips this check only while jq is missing; it never skips a finding.' >&2
exit 1
