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
# Session state: every scanned write leaves one file,
# $DATA/sessions/<pkey>/<session_id>/<tool_use_id>.json, naming the test
# blocks it created or changed (blocks:null when that is unknown: the whole
# file), for the task-end judge. Only a gitignored path and a file the config
# excludes write nothing.
#
# Test seams: TEST_SCAN_SCANNER replaces the scanner, TEST_SCAN_TIMEOUT
# (seconds, default 8, below the hooks.json timeout of 10) bounds it.

set -uo pipefail

# Kill switch before any library is sourced; the launcher's --require-true
# gate already applies it, this keeps a direct run honest too. --enabled is
# for the consumer settings entry /testing:setup check prints for a glob no
# shipped row covers: a settings hook receives no CLAUDE_PLUGIN_OPTION_*
# (probes.md), and adding that entry is the opt-in.
[[ "${1:-}" == --enabled ]] && CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true
[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" ]] || exit 0

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$HOOK_DIR/rewrite-guard.sh"
# shellcheck source=scanner-run.sh
source "$HOOK_DIR/scanner-run.sh"

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
  '.cwd' '.transcript_path' '.tool_response.type? // ""' \
  '.tool_response | objects | has("structuredPatch") | tostring' \
  '[(.tool_response | objects | .structuredPatch)[]?
    | reduce .lines[] as $l ({n: .newStart, out: []};
        if ($l | startswith("+")) then .out += [.n] | .n += 1
        elif ($l | startswith(" ")) then .n += 1 else . end)
    | .out[] | tostring] | join(",")' || exit 0
tool="${HOOK_JQ_FIELDS[0]}" session="${HOOK_JQ_FIELDS[1]}" agent="${HOOK_JQ_FIELDS[2]}"
call="${HOOK_JQ_FIELDS[3]}" pcwd="${HOOK_JQ_FIELDS[4]}" tpath="${HOOK_JQ_FIELDS[5]}"
wtype="${HOOK_JQ_FIELDS[6]}" has_patch="${HOOK_JQ_FIELDS[7]}" lines="${HOOK_JQ_FIELDS[8]}"

testing::data_dir
mkdir -p "$DATA/marks" 2>/dev/null
# No -type: markers are files now, and directories the earlier mkdir scheme left.
find "$DATA/marks" -mindepth 1 -maxdepth 1 -mtime +7 -delete 2>/dev/null
# Session state and the judge's state, at every depth. An empty directory goes
# only once it is an hour old, so a parallel run's fresh mkdir keeps its
# directory until it writes.
find "$DATA"/{sessions,verdicts,locks,relayed,attempts,slots,successors} -mindepth 1 \
  \( -type f -mtime +7 -o -type d -empty -mmin +60 \) -delete 2>/dev/null

out_file="$(mktemp)"
trap 'rm -f "$out_file"' EXIT

# state_write blocks|null: record this write for the task-end judge, one file
# per call so parallel writers never share one, renamed into place so a reader
# never sees half of it. A block the lexer lost is never listed, so a scan that
# lost one records null too. <pkey> is the first 16 hex of the sha256 of the
# project directory, a newline and the transcript directory: a /clear or fork
# successor gets a new session id but keeps both. The project directory is
# CLAUDE_PROJECT_DIR, else the payload cwd, which a Bash cd moves.
state_write() {
  local proj="${CLAUDE_PROJECT_DIR:-$pcwd}" repo="$REPO_ROOT" dir sum sha=(sha256sum)
  [[ "$session" =~ ^[A-Za-z0-9_-]+$ && "$call" =~ ^[A-Za-z0-9_-]+$ && -n "$tpath" && -n "$proj" ]] || return 0
  command -v sha256sum >/dev/null || sha=(shasum -a 256)
  sum="$(printf '%s\n%s' "$proj" "${tpath%[/\\]*}" | "${sha[@]}")" || return 0
  dir="$DATA/sessions/${sum:0:16}/$session"
  ((${HOOK_REPO_ROOT_UNRESOLVED:-0} == 0)) || repo=""
  mkdir -p "$dir" 2>/dev/null || return 0
  if jq -n --arg mode "$1" --rawfile out "$out_file" --rawfile text "$FILE" --arg file "$FILE" \
    --arg repo "$repo" --arg agent "$agent" --argjson create "$create" '{
        file: $file,
        repo: (if $repo == "" then null else $repo end),
        agent_id: (if $agent == "" then null else $agent end),
        create: $create,
        blocks: (if $mode == "null" or ($out | test("lost sync \\(not judged\\): [1-9]")) then null else [$out | splits("\n")
          | capture("^block .*?:(?<start>[0-9]+)-(?<end>[0-9]+) (?<ordinal>[0-9]+) (?<name>.*)$")
          | {name, ordinal: (.ordinal | tonumber), start: (.start | tonumber), end: (.end | tonumber)}] end),
        ok_markers: ([$text | match("cant-fail-ok:"; "g")] | length),
        written_at: (now | todate)}' >"$dir/.$call.tmp" 2>/dev/null; then
    mv -f "$dir/.$call.tmp" "$dir/$call.json"
  else
    rm -f "$dir/.$call.tmp"
  fi
}
create=false
[[ "$tool" == Write && "$wtype" == create ]] && create=true

# mark <path>: create a marker file exclusively (noclobber opens with O_EXCL),
# so exactly one of several racing runs succeeds. mkdir is not atomic under
# uutils coreutils.
mark() { (set -o noclobber && : >"$1") 2>/dev/null; }

# Two `if` rows can match one path (test_x_test.py matches test_*.py and
# *_test.py) and each starts this hook; only the run that creates the marker
# reports.
if [[ -n "$call" ]] && ! mark "$DATA/marks/call-$call"; then exit 0; fi

# A deletion-only patch or an edit with no patch names no written line, so
# no block can be scoped: its state says the whole file.
scope=()
if [[ "$create" == true ]]; then
  :
elif [[ "$has_patch" == true ]]; then
  if [[ -z "$lines" ]]; then
    state_write null
    hook::finish skipped findings array '[]'
  fi
  scope=(--lines "$lines")
elif [[ "$tool" != Write ]]; then
  state_write null
  hook::finish skipped findings array '[]'
fi

# ponytail: patch line numbers go stale if another PostToolUse hook reformats
# the file before this read; the scan then scopes to shifted blocks.
SCANNER="${TEST_SCAN_SCANNER:-$HOOK_DIR/../skills/audit/scripts/cant-fail-scan.sh}"
testing::run_scanner "${TEST_SCAN_TIMEOUT:-8}" "$out_file" --file "$FILE" "${scope[@]}" --blocks
rc=$SCAN_RC

if ((rc != 0)); then
  state_write null
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
state_write blocks

findings="$(grep '^finding \[' "$out_file")"
ctx=""
FINDINGS_JSON='[]'
if [[ -n "$findings" ]]; then
  # The change-detector rules flag tests that fail on harmless changes, and a
  # derived expectation, a snapshot or a weak oracle can fail too; only the
  # rest cannot fail.
  lead="has tests that cannot fail:"
  if ! grep -qv -e rule-constant-restatement -e rule-source-text-read -e rule-recomputed-derived -e rule-snapshot-only -e rule-weak-oracle <<<"$findings"; then
    lead="has tests that check little (derived, weak or snapshot-only oracles):"
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
