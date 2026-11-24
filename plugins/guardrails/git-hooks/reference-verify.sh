#!/bin/sh
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

declined="$(git config --type=bool --get checks.guardrails.reference-verify.declined 2>/dev/null)"
[[ $? -eq 1 ]] && declined="$(git config --type=bool --get checks.git-hooks.declined 2>/dev/null)"
[[ "$declined" == true ]] && exit 0

base_ref=""
if [[ "${1:-}" == --base ]]; then
  base_ref="${2:-}"
  shift 2 2>/dev/null || shift
  if [[ -z "$base_ref" ]]; then
    printf '%s\n' 'reference-verify.sh: --base needs a ref' >&2
    exit 2
  fi
  checks_init pre-push "$@" </dev/null || exit 0
  if ! fork="$(git merge-base "$base_ref" HEAD 2>/dev/null)"; then
    printf 'reference-verify.sh: no merge-base of HEAD and %s, so nothing was checked\n' "$base_ref" >&2
    exit 1
  fi
  printf '%s %s\n' "$fork" "$(git rev-parse HEAD)" >"$CHECKS_TMP/push-ranges"
else
  checks_init pre-push "$@" || exit 0
fi
checks_require_tool jq "https://jqlang.org/download/"

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

TIP=""
BASE=""
MERGE_BASES=()

is_new() {
  if [[ "$CHECKS_MODE" == worktree ]]; then
    ! git ls-files --error-unmatch -- ":(literal)$1" >/dev/null 2>&1 ||
      ! git cat-file -e "HEAD:$1" 2>/dev/null
    return
  fi
  local m
  for m in "$BASE" ${MERGE_BASES[@]+"${MERGE_BASES[@]}"}; do
    git cat-file -e "$m:$1" 2>/dev/null && return 1
  done
  return 0
}

changed_lines() {
  local d s
  checks_changed_lines
  : >"$CHECKS_TMP/copies"
  while IFS= read -r -d '' _ && IFS= read -r -d '' _ && IFS= read -r -d '' d; do
    printf '%s\n' "$d" >>"$CHECKS_TMP/copies"
  done < <(checks_diff --name-status -C --diff-filter=C -z 2>/dev/null)
  [[ -s "$CHECKS_TMP/copies" ]] || return 0
  checks_diff -U0 --text -C --diff-filter=C --src-prefix=a/ --dst-prefix=b/ --inter-hunk-context=0 2>/dev/null |
    awk '
      left > 0 || right > 0 {
        c = substr($0, 1, 1)
        if (c == " ") { left--; right--; next }
        if (c == "-") { left--; next }
        if (c == "+") { right--; next }
        if (c == "\\") next
      }
      /^\+\+\+ / { path = substr($0, 5); sub(/\t$/, "", path); if (path ~ /^b\//) path = substr(path, 3); else path = ""; next }
      /^@@ / {
        split($2, o, ",")
        left = (o[2] == "") ? 1 : o[2] + 0
        split($3, n, ",")
        start = substr(n[1], 2) + 0
        right = (n[2] == "") ? 1 : n[2] + 0
        if (path != "" && right > 0) printf "%s\t%d\t%d\n", path, start, start + right - 1
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

narrow_to_branch() {
  local m s
  ((${#MERGE_BASES[@]})) || return 0
  cp "$CHECKS_TMP/ranges" "$CHECKS_TMP/ranges.push"
  for m in "${MERGE_BASES[@]}"; do
    mv "$CHECKS_TMP/ranges" "$CHECKS_TMP/ranges.kept"
    printf '%s %s\n' "$m" "$TIP" >"$CHECKS_TMP/push-ranges"
    changed_lines
    mv "$CHECKS_TMP/ranges" "$CHECKS_TMP/ranges.merged"
    checks_intersect_ranges "$CHECKS_TMP/ranges.merged" "$CHECKS_TMP/ranges.kept" >"$CHECKS_TMP/ranges"
    s=$?
    if ((s != 0)); then
      printf '%s %s\n' "$BASE" "$TIP" >"$CHECKS_TMP/push-ranges"
      checks_tool_failed awk "$s" 'narrowing the changed lines to the branch'
      mv "$CHECKS_TMP/ranges.push" "$CHECKS_TMP/ranges"
      return 1
    fi
  done
  printf '%s %s\n' "$BASE" "$TIP" >"$CHECKS_TMP/push-ranges"
}

nearest_pushed_base() {
  local r n best="" min=0
  while IFS= read -r r; do
    [[ "$r" != "$BASE" ]] || continue
    n="$(git rev-list --count "$r..$TIP" -- 2>/dev/null)" || continue
    if [[ -z "$best" ]] || ((n < min)); then
      best="$r"
      min="$n"
    fi
  done < <(git for-each-ref --merged="$TIP" --contains="$BASE" --format='%(objectname)' "refs/remotes/$remote/" 2>/dev/null)
  [[ -z "$best" ]] || BASE="$best"
}

pushed_merge_bases() {
  local walk line own=0
  local -a held=()
  MERGE_BASES=()
  walk="$(git rev-list --boundary "$TIP" --not "$BASE" --remotes="$remote" 2>/dev/null)" || return 0
  while IFS= read -r line; do
    if [[ "$line" == -* ]]; then
      [[ "${line#-}" == "$BASE" ]] || held+=("${line#-}")
    elif [[ -n "$line" ]]; then
      own=1
    fi
  done <<<"$walk"
  if ((!own)); then
    [[ "$TIP" == "$BASE" ]] || MERGE_BASES=("$TIP")
    return 0
  fi
  ((${#held[@]})) || return 0
  walk="$(git merge-base --independent "$BASE" "${held[@]}" 2>/dev/null)" || return 0
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "$BASE" ]] || MERGE_BASES+=("$line")
  done <<<"$walk"
}

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
# Each row has a kind, taken from the verifier heading it sits under: a
# stale-path-verify block is advisory and goes to $advisory; any other block,
# and a line before any heading, blocks and goes to stdout.
# The path travels in the environment: awk -v decodes a backslash escape, and
# the path is printed.
report() {
  REPORT_PATH="$1" awk -v whole="$2" -v first="$(first_line "$1")" \
    -v ranges="$CHECKS_TMP/ranges" -v file="$CHECKS_TMP/file" -v adv="$advisory" '
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
    function row(at, msg, k) {
      if (k == "advisory") printf "%s:%s: %s\n", want, at, msg >> adv
      else printf "%s:%s: %s\n", want, at, msg
    }
    BEGIN {
      want = ENVIRON["REPORT_PATH"]
      kind = "blocking"
      while ((getline l < ranges) > 0) { split(l, r, "\t"); if (r[1] == want) { n++; s[n] = r[2] + 0; e[n] = r[3] + 0 } }
      while ((getline l < file) > 0) src[++lines] = l
    }
    /^[ \t]*$/ { next }
    !/^  / {
      if (head != "") row(first, head, kind)
      if (/^stale-path-verify: /) kind = "advisory"
      else if (/^[a-z-]+-verify: /) kind = "blocking"
      head = $0; at = first; next
    }
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
      if (head != "") { row(at, head, kind); head = "" }
      row(at, $0, kind)
    }
    END { if (head != "") row(first, head, kind) }'
}

finding() {
  printf '%s:%s: reference-verify: %s\n' "$1" "$(first_line "$1")" "$2" >>"$out"
}

verified_type() {
  local f="$1"
  case "$f" in
    evals/samples/* | evals/*/samples/* | */evals/samples/* | */evals/*/samples/*) return 1 ;;
    *.md | *.sh | *.bash | *.ps1 | *.psm1) return 0 ;;
    *) return 1 ;;
  esac
}

out="$CHECKS_TMP/findings"
advisory="$CHECKS_TMP/advisory"
: >"$out"
: >"$advisory"

check_range() {
  local f ctx whole s _
  local derived=$'\n' text="$CHECKS_TMP/text" payload="$CHECKS_TMP/payload" guards="$CHECKS_TMP/guards"
  changed_lines
  narrow_to_branch
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
    # A step that fails here would hand the verifiers an empty or partial
    # payload, so the file is reported unchecked instead.
    if ! checks_file_text --tip "$TIP" "$f" >"$CHECKS_TMP/file"; then
      finding "$f" "could not read the file at the pushed tip, so it was not checked; fix that failure, then push again."
      continue
    fi
    whole=0
    s=0
    if [[ "$f" == *[\"\\[:cntrl:]]* ]] || { [[ "$derived" != *$'\n'"$f"$'\n'* ]] && is_new "$f"; }; then
      whole=1
      jq -n --arg p "$PWD/$f" --rawfile c "$CHECKS_TMP/file" \
        '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}' >"$payload" || s=$?
    else
      if ! added_lines "$f" <"$CHECKS_TMP/file" >"$text"; then
        finding "$f" "could not list the lines the push adds, so it was not checked; fix that failure, then push again."
        continue
      fi
      grep -q '[^[:space:]]' "$text" || continue
      jq -n --arg p "$PWD/$f" --rawfile c "$text" \
        '{hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: {file_path: $p, old_string: "", new_string: $c}}' >"$payload" || s=$?
    fi
    if ((s != 0)); then
      finding "$f" "jq exited $s while building the verifiers' input, so it was not checked; fix that failure, then push again."
      continue
    fi
    # git exports GIT_DIR (a linked worktree's git dir) to its hooks; under it
    # `git -C <dir> rev-parse --show-toplevel` answers <dir>, so the verifiers
    # would take the file's own folder for the repository root. They find the
    # repository from the file, as an edit hook does.
    # The verifiers are advisory and exit 0, so any other status, or output
    # jq cannot read, means the file went unchecked.
    (
      unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY \
        GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM
      CLAUDE_PLUGIN_ROOT="$root" checks_bash_run "$run_guards" cli-flag-verify.sh skill-reference-verify.sh stale-path-verify.sh <"$payload" >"$guards" 2>/dev/null
    )
    s=$?
    if ((s != 0)); then
      finding "$f" "run-guards.sh exited $s while running the verifiers, so it was not checked; fix that failure, then push again."
      continue
    fi
    ctx="$(jq -r '.hookSpecificOutput.additionalContext // empty' <"$guards" 2>/dev/null)"
    s=$?
    if ((s != 0)); then
      finding "$f" "jq exited $s while reading the verifiers' output, so it was not checked; fix that failure, then push again."
      continue
    fi
    [[ -n "$ctx" ]] || continue
    report "$f" "$whole" <<<"$ctx" >>"$out"
  done < <(checks_files)
}

tip_is_checkout() {
  [[ "$TIP" == "$(git rev-parse --verify --quiet HEAD 2>/dev/null)" && -z "$(git status --porcelain 2>/dev/null)" ]]
}

if [[ "$CHECKS_MODE" == worktree ]]; then
  check_range
else
  top="$PWD"
  tip_tree="$CHECKS_TMP/tip"
  mkdir -p "$CHECKS_TMP/no-hooks"
  # shellcheck disable=SC2064 # expand now: the path is fixed here
  trap "checks_finish \$?; s=\$?; git -C '$top' worktree prune 2>/dev/null; ((s == 0)) || exit 1" EXIT
  mv "$CHECKS_TMP/push-ranges" "$CHECKS_TMP/all-ranges"
  remote="${CHECKS_ARGS%% *}"
  [[ -n "$remote" ]] || remote=origin
  while read -r BASE TIP <&3; do
    [[ -n "$base_ref" ]] || nearest_pushed_base
    printf '%s %s\n' "$BASE" "$TIP" >"$CHECKS_TMP/push-ranges"
    [[ -n "$base_ref" ]] || pushed_merge_bases
    if tip_is_checkout; then
      check_range
      continue
    fi
    if git -c core.hooksPath="$CHECKS_TMP/no-hooks" worktree add -q --detach "$tip_tree" "$TIP" >/dev/null 2>&1 &&
      cd "$tip_tree"; then
      check_range
      cd "$top" || exit 1
    else
      printf '%s: reference-verify: could not check out this pushed tip, so its range was not checked; fix that failure (disk space, a lock under .git/worktrees), then push again.\n' \
        "$TIP" >>"$out"
    fi
    git worktree remove --force "$tip_tree" >/dev/null 2>&1
    git worktree prune 2>/dev/null
  done 3<"$CHECKS_TMP/all-ranges"
fi

cat "$out" "$advisory" >&2
if [[ -s "$advisory" ]]; then
  printf '%s\n' 'guardrails: a deleted path above is advisory and does not fail the push: correct it if the citation is wrong, and keep it if it records the deletion.' >&2
fi
[[ -s "$out" ]] || exit 0
printf 'guardrails: correct each flag or skill reference above, or fix the failure a reference-verify line names, commit the fix, then push again.\n' >&2
if grep -q ': cli-flag-verify: ' "$out"; then
  printf '%s\n' \
    'guardrails: a cli-flag finding is unverified, not proven wrong. When the flag is right, stop this check in this clone:' \
    'git config checks.guardrails.reference-verify.declined true' >&2
fi
printf '%s\n' 'guardrails: git -c checks.skipmissing=jq skips this check only while jq is missing; it never skips a finding.' >&2
exit 1
