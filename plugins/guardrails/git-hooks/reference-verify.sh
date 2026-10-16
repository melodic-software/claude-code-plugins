#!/usr/bin/env bash
# guardrails pre-commit check: CLI flags, /plugin:skill references and cited
# repository paths in the lines this commit adds.
#
#   reference-verify.sh               the staged changes (git runs it as pre-commit)
#   reference-verify.sh --worktree    the uncommitted changes against HEAD,
#                                     untracked files included
#
# Runs the three verifiers that used to report after every Claude Code edit
# (cli-flag-verify, skill-reference-verify, stale-path-verify) once per changed
# .md, .sh, .bash, .ps1 or .psm1 file, through the plugin's run-guards.sh
# dispatcher, all installed beside this script as entry assets. Each file is
# handed over the way the edit row handed it: a new file as a Write of its whole
# content, a changed file as an Edit whose new text is the lines the commit adds,
# so a finding is always about an added line. The verifiers' own scope gates
# hold (skill references are judged only in a marketplace repository).
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

checks_init pre-commit "$@" || exit 0
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

checks_changed_lines

file_text() {
  if [[ "$CHECKS_MODE" == worktree ]]; then
    cat -- "$1"
  else
    git show ":$1" 2>/dev/null
  fi
}

regular_file() {
  local entry
  if [[ "$CHECKS_MODE" == worktree ]]; then
    [[ -f "$1" && ! -L "$1" ]]
    return
  fi
  entry="$(git ls-files -s -- ":(literal)$1" 2>/dev/null)"
  [[ "$entry" == 100* ]]
}

# is_new <path>: the commit adds the file rather than changing it.
is_new() {
  if [[ "$CHECKS_MODE" == worktree ]]; then
    ! git ls-files --error-unmatch -- ":(literal)$1" >/dev/null 2>&1 ||
      ! git cat-file -e "HEAD:$1" 2>/dev/null
    return
  fi
  ! git cat-file -e "HEAD:$1" 2>/dev/null
}

# added_lines <path>: the lines the commit adds, in order.
added_lines() {
  awk -v want="$1" -v ranges="$CHECKS_TMP/ranges" '
    BEGIN { while ((getline l < ranges) > 0) { split(l, r, "\t"); if (r[1] == want) { n++; s[n] = r[2] + 0; e[n] = r[3] + 0 } } }
    { for (i = 1; i <= n; i++) if (NR >= s[i] && NR <= e[i]) { print; break } }'
}

first_line() {
  awk -v want="$1" -F '\t' '$1 == want { if (min == "" || $2 + 0 < min) min = $2 + 0 } END { print (min == "" ? 1 : min) }' \
    "$CHECKS_TMP/ranges"
}

out="$CHECKS_TMP/findings"
: >"$out"
while IFS= read -r -d '' f; do
  case "$f" in
  *.md | *.sh | *.bash | *.ps1 | *.psm1) ;;
  *) continue ;;
  esac
  git check-ignore -q --no-index -- "$f" 2>/dev/null && continue
  regular_file "$f" || continue
  if is_new "$f"; then
    text="$(file_text "$f"; printf x)"
    text="${text%x}"
    payload="$(jq -n --arg p "$PWD/$f" --arg c "$text" \
      '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}')"
  else
    text="$(file_text "$f" | added_lines "$f"; printf x)"
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

[[ -s "$out" ]] || exit 0
cat "$out" >&2
printf 'guardrails: correct each flag, skill reference or path above in the change, then commit again.\n' >&2
exit 1
