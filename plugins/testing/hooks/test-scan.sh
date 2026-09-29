#!/usr/bin/env bash
# PostToolUse hook: run the can't-fail scanner on the test file just written.
#
# ADVISORY: always exits 0. Findings go back to the writing agent through
# additionalContext; the write has already happened and is never undone.
# Opt-in: hooks.json starts this only through exec-bash.mjs --require-true
# TEST_GUARDS_ENABLED, and only for paths its `if` rows (generated from the
# adapters' files: globs by scripts/gen-hook-filters.sh) match.
#
# Scope (hook-precision rule 1): a Write that creates the file reports every
# test block; an Edit or an overwriting Write reports only blocks that overlap
# the lines the call wrote, read from tool_response.structuredPatch. An Edit
# whose payload carries no patch reports nothing rather than the whole file.
#
# Test seams: TEST_SCAN_SCANNER replaces the scanner, TEST_SCAN_TIMEOUT
# (seconds, default 8, below the hooks.json timeout of 10) bounds it.

set -uo pipefail

# Kill switch before any library is sourced; the launcher's --require-true
# gate already applies it, this keeps a direct run honest too.
[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" ]] || exit 0

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$HOOK_DIR/rewrite-guard.sh"

# --no-membership: the `if` rows bound this hook's scope, and a PostToolUse
# check cannot undo the write, so the CLAUDE_PROJECT_DIR guard only loses
# coverage (see actionlint-check.sh for the Windows short-name case).
hook::begin --no-membership test-scan PostToolUse

if hook::gitignored_out_of_scope false "$FILE"; then
  hook::finish skipped findings array '[]'
fi

# shellcheck disable=SC2016  # jq programs, not shell expansions
# shellcheck disable=SC2016  # jq programs, not shell expansions
hook::jq_fields "$INPUT" '.tool_name' '.session_id' '.agent_id // ""' '.tool_use_id' \
  '.tool_response.type? // ""' \
  '.tool_response | objects | has("structuredPatch") | tostring' \
  '[(.tool_response | objects | .structuredPatch)[]?
    | reduce .lines[] as $l ({n: .newStart, out: []};
        if ($l | startswith("+")) then .out += [.n] | .n += 1
        elif ($l | startswith(" ")) then .n += 1 else . end)
    | .out[] | tostring] | join(",")' || exit 0
tool="${HOOK_JQ_FIELDS[0]}" session="${HOOK_JQ_FIELDS[1]}" agent="${HOOK_JQ_FIELDS[2]}"
call="${HOOK_JQ_FIELDS[3]}" wtype="${HOOK_JQ_FIELDS[4]}" has_patch="${HOOK_JQ_FIELDS[5]}"
lines="${HOOK_JQ_FIELDS[6]}"

DATA="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/testing-plugin-data}"
mkdir -p "$DATA/marks" 2>/dev/null
find "$DATA/marks" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null

# Two `if` rows can match one path (test_x_test.py matches test_*.py and
# *_test.py) and each starts this hook; mkdir is atomic, so one run wins.
if [[ -n "$call" ]] && ! mkdir "$DATA/marks/call-$call" 2>/dev/null; then exit 0; fi

scope=()
if [[ "$tool" == Write && "$wtype" == create ]]; then
  :
elif [[ "$has_patch" == true ]]; then
  [[ -n "$lines" ]] || hook::finish skipped findings array '[]'
  scope=(--lines "$lines")
elif [[ "$tool" != Write ]]; then
  hook::finish skipped findings array '[]'
fi

# ponytail: patch line numbers go stale if another PostToolUse hook reformats
# the file before this read; the scan then scopes to shifted blocks.
SCANNER="${TEST_SCAN_SCANNER:-$HOOK_DIR/../skills/audit/scripts/cant-fail-scan.sh}"
out_file="$(mktemp)"
trap 'rm -f "$out_file"' EXIT
bash "$SCANNER" --file "$FILE" "${scope[@]}" >"$out_file" 2>&1 &
pid=$!
(
  sleep "${TEST_SCAN_TIMEOUT:-8}"
  kill "$pid"
) >/dev/null 2>&1 &
watchdog=$!
wait "$pid"
rc=$?
kill "$watchdog" 2>/dev/null

if ((rc != 0)); then
  why="scanner exited $rc"
  ((rc > 128)) && why="scanner timed out after ${TEST_SCAN_TIMEOUT:-8}s"
  printf '%s test-scan: %s: %s\n' "$(date -u +%FT%TZ)" "$FILE" "$why" >>"$DATA/test-scan.log"
  printf 'test-scan: %s: %s\n' "$FILE" "$why" >&2
  hook::finish error findings array '[]'
fi

findings="$(grep '^finding \[' "$out_file")"
ctx=""
FINDINGS_JSON='[]'
if [[ -n "$findings" ]]; then
  hook::findings_to ctx "testing: $FILE_BASE has tests that cannot fail:" "$findings" FINDINGS_JSON
  if [[ "$findings" == *rule-recomputed-expectation* ]]; then
    ctx+=$'\n'"Before you continue, state where the expected value in each flagged assertion comes from (a spec, a bug report, a hand-computed literal). If it comes from running the code under test, replace it with a value worked out independently."
  fi
fi

key="$(printf '%s|%s|%s' "$session" "$agent" "$FILE" | cksum)"
if mkdir "$DATA/marks/note-${key%% *}" 2>/dev/null; then
  ctx+="${ctx:+$'\n'}Tests here should fail when the behavior they cover breaks. Load the testing:test-value skill for where expected values must come from and what makes a test worth keeping."
fi

((${#ctx} < 10000)) || ctx="${ctx:0:9800}"$'\n'"(truncated; run /testing:audit for the full list)"
hook::finish --context "$ctx" ok findings array "$FINDINGS_JSON"
