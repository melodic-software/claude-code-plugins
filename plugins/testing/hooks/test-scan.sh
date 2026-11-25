#!/usr/bin/env bash
set -uo pipefail

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

hook::begin --no-membership test-scan PostToolUse

if hook::gitignored_out_of_scope false "$FILE"; then
  hook::finish skipped findings array '[]'
fi

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
find "$DATA/marks" -mindepth 1 -maxdepth 1 -mtime +7 -delete 2>/dev/null
find "$DATA"/{sessions,verdicts,locks,relayed,attempts,slots,successors,pending,runs,findings,derive} -mindepth 1 \
  \( -type f -mtime +7 -o -type d -empty -mmin +60 \) -delete 2>/dev/null

out_file="$(mktemp)"
trap 'rm -f "$out_file"' EXIT

state_write() {
  local repo="$REPO_ROOT" dir
  testing::record_skip "$FILE" && return 0
  [[ "$session" =~ ^[A-Za-z0-9_-]+$ && "$call" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
  testing::pkey "${CLAUDE_PROJECT_DIR:-$pcwd}" "$tpath" || return 0
  dir="$DATA/sessions/$PKEY/$session"
  ((${HOOK_REPO_ROOT_UNRESOLVED:-0} == 0)) || repo=""
  mkdir -p "$dir" 2>/dev/null || return 0
  if jq -n --arg mode "$1" --rawfile out "$out_file" --rawfile text "$FILE" --arg file "$FILE" \
    --arg repo "$repo" --arg agent "$agent" --argjson create "$create" --arg lines "$lines" '{
        file: $file,
        repo: (if $repo == "" then null else $repo end),
        agent_id: (if $agent == "" then null else $agent end),
        create: $create,
        blocks: (if $mode == "null" or ($out | test("lost sync \\(not judged\\): [1-9]")) then null else [$out | splits("\n")
          | capture("^block .*?:(?<start>[0-9]+)-(?<end>[0-9]+) (?<ordinal>[0-9]+) (?<name>.*)$")
          | {name, ordinal: (.ordinal | tonumber), start: (.start | tonumber), end: (.end | tonumber)}] end),
        lines: (if $lines == "" then null else $lines | split(",") | map(tonumber) end),
        ok_markers: ([$text | match("cant-fail-ok:"; "g")] | length),
        written_at: (now | todate)}' >"$dir/.$call.tmp" 2>/dev/null; then
    mv -f "$dir/.$call.tmp" "$dir/$call.json"
  else
    rm -f "$dir/.$call.tmp"
  fi
}
create=false
[[ "$tool" == Write && "$wtype" == create ]] && create=true

mark() { (set -o noclobber && : >"$1") 2>/dev/null; }

if [[ -n "$call" ]] && ! mark "$DATA/marks/call-$call"; then exit 0; fi

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

SCANNER="${TEST_SCAN_SCANNER:-$HOOK_DIR/../skills/audit/scripts/cant-fail-scan.sh}"
scan_timeout="${TEST_SCAN_TIMEOUT:-8}"
testing::run_scanner "$scan_timeout" "$out_file" --file "$FILE" "${scope[@]}" --blocks --brief
rc=$SCAN_RC

if ((rc != 0)); then
  state_write null
  why="scanner exited $rc"
  ((rc > 128)) && why="scanner timed out after ${scan_timeout}s"
  cfg_err=""
  if grep -q -e '^ERROR: the testing config did not resolve' -e '^ERROR: adapter load failed' "$out_file"; then
    cfg_err="$(grep -v -m1 '^resolve-config: warning: ' < <(grep -E '^(resolve-config|adapter-load): ' "$out_file"))"
    why="${cfg_err:-$why}"
  fi
  printf '%s test-scan: %s: %s\n' "$(date -u +%FT%TZ)" "$FILE" "$why" >>"$DATA/test-scan.log"
  printf 'test-scan: %s: %s\n' "$FILE" "$why" >&2
  [[ -z "$cfg_err" ]] || hook::finish --context "testing: the testing config is invalid, so test-scan did not check $FILE_BASE: $cfg_err" error findings array '[]'
  hook::finish error findings array '[]'
fi

if grep -q '^  test files: 0 examined' "$out_file"; then
  hook::finish skipped findings array '[]'
fi
state_write blocks

findings="$(sed -n 's/^finding \[/[/p' "$out_file")"
ctx=""
FINDINGS_JSON='[]'
if [[ -n "$findings" ]]; then
  lead="has tests that cannot fail:"
  if ! grep -qv -e rule-constant-restatement -e rule-source-text-read -e rule-recomputed-derived -e rule-snapshot-only -e rule-weak-oracle -e rule-throw-only-oracle <<<"$findings"; then
    lead="has tests that check little (derived, weak, throw-only or snapshot-only oracles):"
    grep -qv -e rule-constant-restatement -e rule-source-text-read <<<"$findings" ||
      lead="has tests that fail on harmless changes (change detectors):"
  fi
  hook::findings_to ctx "testing: $FILE_BASE $lead" "$findings" FINDINGS_JSON \
    --max 10 --more "/testing:audit lists the rest"
  actions="$(sed -n 's/^action \[\([^]]*\)\] /Action [\1]: /p' "$out_file")"
  [[ -z "$actions" ]] || ctx+=$'\n'"$actions"
  CLAUDE_PLUGIN_DATA="$DATA" hook::once_per_file testing-note "$INPUT" "$FILE" &&
    ctx+=$'\n'"/testing:test-value covers where expected values come from."
fi

((${#ctx} < 10000)) || ctx="${ctx:0:9800}"$'\n'"(truncated; /testing:audit lists the rest)"

hook::finish --context "$ctx" ok findings array "$FINDINGS_JSON"
