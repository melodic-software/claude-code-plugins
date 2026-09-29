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
# gate already applies it, this keeps a direct run honest too. --enabled is
# for the consumer settings entry /testing:setup check prints for a glob no
# shipped row covers: a settings hook receives no CLAUDE_PLUGIN_OPTION_*
# (probes.md), and adding that entry is the opt-in.
[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" || "${1:-}" == --enabled ]] || exit 0

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

# The consumer settings entry gets no CLAUDE_PLUGIN_DATA; it derives the same
# directory from this copy's cache path (~/.claude/plugins/cache/<mkt>/testing/
# <version>/hooks), so a call through both paths shares one set of markers.
DATA="${CLAUDE_PLUGIN_DATA:-}"
if [[ -z "$DATA" ]]; then
  DATA="${XDG_STATE_HOME:-${HOME:-}/.local/state}/claude-testing"
  rest="$(cd "$HOOK_DIR/.." && pwd)"
  rest="${rest#"${HOME:-}"/.claude/plugins/cache/}"
  if [[ "$rest" =~ ^([^/]+)/testing/[^/]+$ ]]; then
    mkt="${BASH_REMATCH[1]}"
    DATA="${HOME:-}/.claude/plugins/data/testing-${mkt//[^A-Za-z0-9_-]/-}"
  fi
fi
mkdir -p "$DATA/marks" 2>/dev/null
# No -type: markers are files now, and directories the earlier mkdir scheme left.
find "$DATA/marks" -mindepth 1 -maxdepth 1 -mtime +7 -delete 2>/dev/null

# mark <path>: create a marker file exclusively (noclobber opens with O_EXCL),
# so exactly one of several racing runs succeeds. mkdir is not atomic under
# uutils coreutils.
mark() { (set -o noclobber && : >"$1") 2>/dev/null; }

# Two `if` rows can match one path (test_x_test.py matches test_*.py and
# *_test.py) and each starts this hook; only the run that creates the marker
# reports.
if [[ -n "$call" ]] && ! mark "$DATA/marks/call-$call"; then exit 0; fi

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
  # A config the scanner refuses is the agent's to fix: log the resolver's or
  # loader's own message and name it, at its file and line, in the context.
  cfg_err=""
  if grep -q -e '^ERROR: .claude/testing.yaml did not resolve' -e '^ERROR: adapter load failed' "$out_file"; then
    cfg_err="$(grep -m1 -E '^(resolve-config|adapter-load): ' "$out_file")"
    why="${cfg_err:-$why}"
  fi
  printf '%s test-scan: %s: %s\n' "$(date -u +%FT%TZ)" "$FILE" "$why" >>"$DATA/test-scan.log"
  printf 'test-scan: %s: %s\n' "$FILE" "$why" >&2
  [[ -z "$cfg_err" ]] || hook::finish --context "testing: the testing config is invalid, so test-scan did not check $FILE_BASE: $cfg_err" error findings array '[]'
  hook::finish error findings array '[]'
fi

# The scanner examined nothing: .claude/testing.yaml excluded the path or
# disabled its adapter. No findings and no note.
if grep -q '^  test files: 0 examined' "$out_file"; then
  hook::finish skipped findings array '[]'
fi

findings="$(grep '^finding \[' "$out_file")"
ctx=""
FINDINGS_JSON='[]'
if [[ -n "$findings" ]]; then
  # The change-detector rules flag tests that fail on harmless changes, and a
  # snapshot or weak oracle can fail too; only the rest cannot fail.
  lead="has tests that cannot fail:"
  if ! grep -qv -e rule-constant-restatement -e rule-source-text-read -e rule-snapshot-only -e rule-weak-oracle <<<"$findings"; then
    lead="has tests that check little (weak or snapshot-only oracles):"
    grep -qv -e rule-constant-restatement -e rule-source-text-read <<<"$findings" ||
      lead="has tests that fail on harmless changes (change detectors):"
  fi
  hook::findings_to ctx "testing: $FILE_BASE $lead" "$findings" FINDINGS_JSON
  if [[ "$findings" == *rule-recomputed-expectation* || "$findings" == *rule-constant-restatement* || "$findings" == *rule-recomputed-derived* ]]; then
    ctx+=$'\n'"Before you continue, state where the expected value in each flagged assertion comes from (a spec, a bug report, a hand-computed literal). If it comes from running the code under test, replace it with a value worked out independently."
  fi
fi

key="$(printf '%s|%s|%s' "$session" "$agent" "$FILE" | cksum)"
if mark "$DATA/marks/note-${key%% *}"; then
  ctx+="${ctx:+$'\n'}Tests here should fail when the behavior they cover breaks. Load the testing:test-value skill for where expected values must come from and what makes a test worth keeping."
fi

((${#ctx} < 10000)) || ctx="${ctx:0:9800}"$'\n'"(truncated; run /testing:audit for the full list)"
hook::finish --context "$ctx" ok findings array "$FINDINGS_JSON"
