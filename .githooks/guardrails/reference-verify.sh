#!/usr/bin/env bash
# guardrails reference-verify sha256:071d805fd1ce47521d3f6fbb3bf0f266507762648b9690bea62d9c1f691f91da
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
# .md, .sh, .bash, .ps1 or .psm1 file, through the plugin's run-guards.sh
# dispatcher, all installed beside this script as entry assets. Each file is
# handed over the way the edit row handed it: a file new to the range as a
# Write of its whole content, a changed file as an Edit whose new text is the
# lines the range adds, so a finding is always about an added line. The
# verifiers' own scope gates hold (skill references are judged only in a
# marketplace repository). It runs at pre-push, not pre-commit, because its
# cost is over the commit budget (check-placement convention, measured rows).
#
# The ranges come from the check lib: one per pushed ref, a new branch from its
# merge-base with the remote's default branch, a deletion skipped. A hook
# manager that keeps stdin from this script (lefthook passes it to only one
# use_stdin job) leaves the lib's fallback: the current branch against its
# upstream. Each range is checked on its own, in that range's tip: the
# checkout when HEAD is the tip and the tree is clean, else a temporary
# detached worktree of the tip, removed afterwards.
#
# A finding prints as "<path>:<line>: <message>" on stderr, the line being the
# file's first added line, and exits 1. Missing jq follows the check-placement
# contract: checks.skipmissing, else fail for an agent and a notice for a person.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
here="$(cd "$here" && pwd)"
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

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
TIP=""
BASE=""

# is_new <path>: the range adds the file rather than changing it.
is_new() {
  if [[ "$CHECKS_MODE" == worktree ]]; then
    ! git ls-files --error-unmatch -- ":(literal)$1" >/dev/null 2>&1 ||
      ! git cat-file -e "HEAD:$1" 2>/dev/null
    return
  fi
  ! git cat-file -e "$BASE:$1" 2>/dev/null
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

# verified_type <path>: an extension the verifiers read.
verified_type() {
  local f="$1"
  case "$f" in
    *.md | *.sh | *.bash | *.ps1 | *.psm1) return 0 ;;
    *) return 1 ;;
  esac
}

out="$CHECKS_TMP/findings"
: >"$out"

# check_range: every file the current range (or the worktree) changes.
check_range() {
  local f text payload ctx line msg _
  local renamed=$'\n'
  checks_changed_lines
  # A rename's destination is missing from the base but is no new text: only
  # the lines the range adds to it are judged.
  while IFS= read -r -d '' _ && IFS= read -r -d '' _ && IFS= read -r -d '' f; do
    renamed+="$f"$'\n'
  done < <(checks_diff --name-status -M --diff-filter=R -z 2>/dev/null)
  while IFS= read -r -d '' f; do
    verified_type "$f" || continue
    checks_regular_file --tip "$TIP" "$f" || continue
    # Git quotes a name holding a quote, a backslash or a control byte whatever
    # core.quotePath says, so the range table has no entry for it: such a file
    # is judged whole, as a new one is.
    if [[ "$f" == *[\"\\[:cntrl:]]* ]] || { [[ "$renamed" != *$'\n'"$f"$'\n'* ]] && is_new "$f"; }; then
      text="$(
        checks_file_text --tip "$TIP" "$f"
        printf x
      )"
      text="${text%x}"
      payload="$(jq -n --arg p "$PWD/$f" --arg c "$text" \
        '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}')"
    else
      text="$(
        checks_file_text --tip "$TIP" "$f" | added_lines "$f"
        printf x
      )"
      text="${text%x}"
      [[ -n "${text//[[:space:]]/}" ]] || continue
      payload="$(jq -n --arg p "$PWD/$f" --arg c "$text" \
        '{hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: {file_path: $p, old_string: "", new_string: $c}}')"
    fi
    ctx="$(printf '%s' "$payload" |
      CLAUDE_PLUGIN_ROOT="$root" bash "$run_guards" cli-flag-verify.sh skill-reference-verify.sh stale-path-verify.sh 2>/dev/null |
      jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
    [[ -n "$ctx" ]] || continue
    line="$(first_line "$f")"
    while IFS= read -r msg; do
      [[ -n "${msg//[[:space:]]/}" ]] && printf '%s:%s: %s\n' "$f" "$line" "$msg"
    done <<<"$ctx" >>"$out"
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
  # shellcheck disable=SC2064 # expand now: both paths are fixed here
  trap "rm -rf '$CHECKS_TMP'; git -C '$top' worktree prune 2>/dev/null" EXIT
  mv "$CHECKS_TMP/push-ranges" "$CHECKS_TMP/all-ranges"
  while read -r BASE TIP <&3; do
    printf '%s %s\n' "$BASE" "$TIP" >"$CHECKS_TMP/push-ranges"
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
