#!/usr/bin/env bash
# PostToolUse Bash hook: run test-scan on the test files a Bash call changed.
#
# ADVISORY: always exits 0. Opt-in: hooks.json starts this only through
# exec-bash.mjs --require-true TEST_GUARDS_ENABLED.
#
# Claude Code adds tool_response.bashEditDiff (best-effort beta) to a Bash
# payload when bashEditDiffEnabled is true in user, --settings or managed
# settings, or CLAUDE_CODE_BASH_EDIT_DIFF=1 (probes.md). A payload without it
# exits here before any parsing. Otherwise each changed path whose basename
# matches a test-file glob (the Write rows of hooks.json) goes to test-scan.sh as a Write (created
# file) or an Edit (its hunks as structuredPatch), so the scan scope follows
# hook-precision rule 1 exactly as for a Write or Edit. changedFiles lists
# every path but only the first five carry hunks; a path without hunks reports
# nothing.
#
# Each file's payload carries the call's session_id, transcript_path and cwd,
# and <tool_use_id>-<n> as its own id, so test-scan.sh leaves the per-write
# session record the task-end judge reads, as for a Write or Edit.
#
# test-scan.sh's own stderr (a scanner that failed or timed out) passes
# through, as on the Write and Edit route.
#
# Test seams: TEST_SCAN_TIMEOUT is passed through to test-scan.sh; unset, each
# file gets an equal share of 8 seconds, inside the hooks.json timeout of 10.

set -uo pipefail

[[ "${1:-}" == --enabled ]] && CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true
[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" ]] || exit 0

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

MAX_FILES=4

hook::buffer_stdin_to INPUT || exit 0
# Substring check first: jq stays the authority, stdout can carry the word too.
[[ "$INPUT" == *'"bashEditDiff"'* ]] || exit 0
hook::require_jq PostToolUse testing "$INPUT"

# The globs are this plugin's own Write rows in hooks.json, generated from the
# adapters' files: lists, so one jq call reads them along with the paths.
globs=()
paths=()
while IFS= read -r line; do
  line="${line%$'\r'}"
  p="${line:1}"
  case "$line" in
  G?*) globs+=("$p") ;;
  P?*) ! hook::path_matches "${p##*[/\\]}" "${globs[@]}" || paths+=("$p") ;;
  *) ;;
  esac
done < <(printf '%s' "$INPUT" | jq -r --slurpfile h "$HOOK_DIR/hooks.json" '
  ($h[0].hooks.PostToolUse[] | select(.matcher == "Write|Edit") | .hooks[].if
    | select(startswith("Write(")) | "G" + .[6:-1]),
  (.tool_response.bashEditDiff.changedFiles[]? | strings | "P" + .)' 2>/dev/null)
((${#paths[@]})) || exit 0
# ponytail: test files past the cap are not scanned; raise it with the hook timeout.
paths=("${paths[@]:0:MAX_FILES}")

export TEST_SCAN_TIMEOUT="${TEST_SCAN_TIMEOUT:-$((8 / ${#paths[@]}))}"
docs=()
n=0
for p in "${paths[@]}"; do
  n=$((n + 1))
  # The file's entry in files[] has the hunks and the created flag; a path past
  # the fifth has neither, so it becomes an Edit with an empty patch.
  one="$(printf '%s' "$INPUT" | jq -c --arg f "$p" --arg n "$n" '
    (.tool_response.bashEditDiff.files // [] | map(select(.filePath == $f)) | first // {}) as $d
    | {hook_event_name: "PostToolUse",
       tool_name: (if $d.created then "Write" else "Edit" end),
       session_id: (.session_id // ""), agent_id: (.agent_id // ""),
       tool_use_id: "\(.tool_use_id // "")-\($n)",
       transcript_path: (.transcript_path // ""), cwd: (.cwd // ""),
       tool_input: {file_path: $f},
       tool_response: (if $d.created then {type: "create", structuredPatch: []}
                       else {type: "update", structuredPatch: ($d.hunks // [])} end)}
    | if .agent_id == "" then del(.agent_id) else . end' 2>/dev/null |
    bash "$HOOK_DIR/test-scan.sh" "${1:-}")" || continue
  [[ -n "$one" ]] && docs+=("$one")
done

((${#docs[@]})) || exit 0
if ((${#docs[@]} == 1)); then
  printf '%s\n' "${docs[0]}"
else
  # One document per hook: join the context the per-file runs returned.
  printf '%s\n' "${docs[@]}" | jq -sc '
    {hookSpecificOutput: {hookEventName: "PostToolUse",
       additionalContext: (map(.hookSpecificOutput.additionalContext // empty) | join("\n\n"))}}
    | if .hookSpecificOutput.additionalContext == "" then empty else . end'
fi
exit 0
