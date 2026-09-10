#!/usr/bin/env bash
# Contract test for audit-event-emitter.sh (claude-ops plugin). Black-box.
#
# The emitter serves seven audit rows from one script, dispatching on the
# payload's hook_event_name, so the suite is a table over those rows: each row's
# telemetry `hook` id, `hook_event`, `status` and `data.subject` are asserted
# from one loop, and so are its kill switch, its unwired behavior and its
# missing-required-field skip. What a row does BEYOND that table — the
# privacy reductions, the InstructionsLoaded session_start filter, and the
# UserPromptExpansion second store — follows the table in its own section.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/audit-event-emitter.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

# A non-git project root, so hook::repo_root answers PROJ itself and the
# InstructionsLoaded row's path reduction is deterministic. The
# UserPromptExpansion row writes its second store under a per-case project.
PROJ="$TEST_TMPDIR/proj"
mkdir -p "$PROJ/.claude/rules"
: >"$PROJ/.claude/rules/x.md"

# --- The row table ----------------------------------------------------------
# Tab-separated: id, switch suffix, payload, hook id, hook_event, status,
# data.subject, and a payload that reaches the row with its required field
# missing. `%PROJ%` expands to the fixture project root.
ROWS=(
  $'api-error\tAPI_ERROR_AUDIT\t{"session_id":"sess-1","hook_event_name":"StopFailure","error":"rate_limit"}\tapi-error-audit\tStopFailure\terror\trate_limit\t{"hook_event_name":"StopFailure"}'
  $'config-change\tCONFIG_CHANGE_AUDIT\t{"session_id":"sess-1","hook_event_name":"ConfigChange","source":"project_settings"}\tconfig-change-audit\tConfigChange\tok\tproject_settings\t{"hook_event_name":"ConfigChange"}'
  $'pre-compact\tPRE_COMPACT_AUDIT\t{"session_id":"sess-1","hook_event_name":"PreCompact","trigger":"auto"}\tpre-compact-audit\tPreCompact\tok\tauto\t{"hook_event_name":"PreCompact"}'
  $'tool-failure\tTOOL_FAILURE_AUDIT\t{"session_id":"sess-1","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"FOO=bar dotnet build"}}\ttool-failure-audit\tPostToolUseFailure\terror\tBash:dotnet\t{"hook_event_name":"PostToolUseFailure","tool_input":{"command":"ls"}}'
  $'permission-denied\tPERMISSION_DENIED_AUDIT\t{"session_id":"sess-1","hook_event_name":"PermissionDenied","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}\tpermission-denied-audit\tPermissionDenied\tblocked\tBash:git\t{"hook_event_name":"PermissionDenied","tool_input":{"command":"ls"}}'
  $'instructions-loaded\tINSTRUCTIONS_LOADED_AUDIT\t{"session_id":"sess-1","hook_event_name":"InstructionsLoaded","file_path":"%PROJ%/.claude/rules/x.md","load_reason":"path_glob_match"}\tinstructions-loaded-audit\tInstructionsLoaded\tok\t.claude/rules/x.md:path_glob_match\t{"hook_event_name":"InstructionsLoaded"}'
  $'skill-expansion\tSKILL_USAGE_AUDIT\t{"session_id":"sess-1","hook_event_name":"UserPromptExpansion","command_name":"/research","expansion_type":"slash_command"}\tskill-usage-audit\tUserPromptExpansion\tok\tSkill:research\t{"hook_event_name":"UserPromptExpansion","expansion_type":"slash_command"}'
)

n=0
for row in "${ROWS[@]}"; do
  n=$((n + 1))
  IFS=$'\t' read -r id switch payload hook_id event status subject missing <<<"$row"
  payload="${payload//%PROJ%/$PROJ}"
  # Each row gets its own project root so the UserPromptExpansion second store
  # cannot be confused with another case's.
  rowproj="$TEST_TMPDIR/rowproj-$id"
  mkdir -p "$rowproj/.claude/rules"
  : >"$rowproj/.claude/rules/x.md"

  # --- the envelope this row emits -----------------------------------------
  TEL="$TEST_TMPDIR/$id.json"
  if emit_envelope "$HOOK" "$payload" "$TEL" CLAUDE_PROJECT_DIR="$PROJ"; then
    assert_eq "$id: hook id" "$hook_id" "$(jq -r '.hook' "$TEL")"
    assert_eq "$id: hook_event" "$event" "$(jq -r '.hook_event' "$TEL")"
    assert_eq "$id: status" "$status" "$(jq -r '.status' "$TEL")"
    assert_eq "$id: data.subject" "$subject" "$(jq -r '.data.subject' "$TEL")"
    assert_eq "$id: schema_version" "1.1" "$(jq -r '.schema_version' "$TEL")"
    assert_eq "$id: spine session_id (1.1)" "sess-1" "$(jq -r '.session_id' "$TEL")"
    assert_eq "$id: data.session_id still sent for a 1.0 sink" "sess-1" "$(jq -r '.data.session_id' "$TEL")"
  else
    bad "$id: no envelope written when a sink is wired"
  fi

  # --- this row's kill switch, and only this row's -------------------------
  expect_no_envelope "$id: kill switch → no envelope" \
    "$HOOK" "$payload" "$TEST_TMPDIR/$id.killed.json" \
    CLAUDE_PROJECT_DIR="$rowproj" "CLAUDE_PLUGIN_OPTION_${switch}_ENABLED=false"

  # --- unwired: exit 0, and nothing on stdout or stderr --------------------
  OUT=$(env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$rowproj" bash "$HOOK" <<<"$payload" 2>&1)
  RC=$?
  assert_exit "$id: unwired → exit 0" 0 "$RC"
  assert_silent "$id: unwired → silent" "$OUT"

  # --- the required field is missing: a silent skip ------------------------
  expect_no_envelope "$id: missing required field → no envelope" \
    "$HOOK" "$missing" "$TEST_TMPDIR/$id.missing.json" CLAUDE_PROJECT_DIR="$rowproj"
done
assert_eq "every row in the table was driven" 7 "$n"

# --- One row's switch does not silence another ------------------------------
TELX="$TEST_TMPDIR/cross-switch.json"
if emit_envelope "$HOOK" \
  '{"session_id":"sess-1","hook_event_name":"PreCompact","trigger":"auto"}' "$TELX" \
  CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_OPTION_API_ERROR_AUDIT_ENABLED=false; then
  assert_eq "another row's switch leaves this one emitting" "pre-compact-audit" "$(jq -r '.hook' "$TELX")"
else
  bad "a disabled sibling row suppressed pre-compact-audit"
fi

# --- No row for the event → silent skip -------------------------------------
expect_no_envelope "unknown event → no envelope" \
  "$HOOK" '{"session_id":"sess-1","hook_event_name":"SessionStart","source":"startup"}' \
  "$TEST_TMPDIR/unknown-event.json" CLAUDE_PROJECT_DIR="$PROJ"
expect_no_envelope "no hook_event_name → no envelope" \
  "$HOOK" '{"session_id":"sess-1","error":"rate_limit"}' \
  "$TEST_TMPDIR/no-event.json" CLAUDE_PROJECT_DIR="$PROJ"

# --- Privacy: the tool rows never carry a command body ----------------------
for probe in "PostToolUseFailure tool-failure" "PermissionDenied permission-denied"; do
  read -r pev pid <<<"$probe"
  TELP="$TEST_TMPDIR/$pid.privacy.json"
  if emit_envelope "$HOOK" \
    "{\"hook_event_name\":\"$pev\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"TOKEN=\\\"secret value\\\" curl https://x\"}}" \
    "$TELP" CLAUDE_PROJECT_DIR="$PROJ"; then
    assert_eq "$pid: quoted assignment → bare Bash subject" "Bash" "$(jq -r '.data.subject' "$TELP")"
    assert_absent "$pid: no value fragment leaked" "$(cat "$TELP")" "secret"
    assert_absent "$pid: no value fragment leaked (2)" "$(cat "$TELP")" "value"
    assert_absent "$pid: no command body leaked" "$(cat "$TELP")" "curl"
  else
    bad "$pid: no envelope for a quoted-assignment command"
  fi

  TELW="$TEST_TMPDIR/$pid.nonbash.json"
  if emit_envelope "$HOOK" \
    "{\"hook_event_name\":\"$pev\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"secret.env\"}}" \
    "$TELW" CLAUDE_PROJECT_DIR="$PROJ"; then
    assert_eq "$pid: non-Bash subject = tool name" "Write" "$(jq -r '.data.subject' "$TELW")"
    assert_eq "$pid: data.tool" "Write" "$(jq -r '.data.tool' "$TELW")"
    assert_absent "$pid: file_path not captured" "$(cat "$TELW")" "secret.env"
  else
    bad "$pid: no envelope for a non-Bash tool"
  fi
done

# --- InstructionsLoaded: path reduction and the session_start filter --------
TELB="$TEST_TMPDIR/il-outside.json"
OUTSIDE="$TEST_TMPDIR/elsewhere/private-dir/CLAUDE.md"
if emit_envelope "$HOOK" \
  "$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$OUTSIDE" '{hook_event_name:"InstructionsLoaded", file_path:$fp, load_reason:"include"}')" \
  "$TELB" CLAUDE_PROJECT_DIR="$PROJ"; then
  assert_eq "instructions-loaded: out-of-repo → basename subject" "CLAUDE.md:include" "$(jq -r '.data.subject' "$TELB")"
  assert_absent "instructions-loaded: no parent dir leaked" "$(cat "$TELB")" "private-dir"
else
  bad "instructions-loaded: no envelope for an out-of-repo path"
fi

TELA="$TEST_TMPDIR/il-inrepo.json"
if emit_envelope "$HOOK" \
  "$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$PROJ/.claude/rules/x.md" '{hook_event_name:"InstructionsLoaded", file_path:$fp, load_reason:"path_glob_match"}')" \
  "$TELA" CLAUDE_PROJECT_DIR="$PROJ"; then
  assert_absent "instructions-loaded: no absolute prefix leaked" "$(cat "$TELA")" "$PROJ"
else
  bad "instructions-loaded: no envelope for an in-repo path"
fi

SS_PAYLOAD="$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$PROJ/CLAUDE.md" '{hook_event_name:"InstructionsLoaded", file_path:$fp, load_reason:"session_start"}')"
expect_no_envelope "instructions-loaded: session_start filtered by default" \
  "$HOOK" "$SS_PAYLOAD" "$TEST_TMPDIR/il-ss.json" CLAUDE_PROJECT_DIR="$PROJ"

TELO="$TEST_TMPDIR/il-ss-opt-in.json"
if emit_envelope "$HOOK" "$SS_PAYLOAD" "$TELO" CLAUDE_PROJECT_DIR="$PROJ" \
  CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true; then
  assert_eq "instructions-loaded: session_start opt-in subject" "CLAUDE.md:session_start" "$(jq -r '.data.subject' "$TELO")"
else
  bad "instructions-loaded: session_start opt-in did not emit"
fi

# --- UserPromptExpansion: the second store, written without a sink ----------
EXP='{"hook_event_name":"UserPromptExpansion","command_name":"/research","expansion_type":"slash_command"}'

PROJS="$TEST_TMPDIR/exp-store"
mkdir -p "$PROJS"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJS" bash "$HOOK" <<<"$EXP" >/dev/null 2>&1
STORE="$PROJS/.claude/observability/skill-usage.jsonl"
if [[ -s "$STORE" ]]; then
  assert_eq "second store event" "SkillUse" "$(jq -r '.event' "$STORE")"
  assert_eq "second store skill (slash stripped)" "research" "$(jq -r '.skill' "$STORE")"
  assert_eq "second store hook (unified)" "skill-usage-audit" "$(jq -r '.hook' "$STORE")"
  assert_eq "second store source" "expansion" "$(jq -r '.source' "$STORE")"
  assert_eq "second store expansion_type" "slash_command" "$(jq -r '.expansion_type' "$STORE")"
  jq -e -s 'all(.[]; (.ts|type)=="string" and .event=="SkillUse"
    and (.skill|type)=="string" and (.branch|type)=="string"
    and (.project|type)=="string" and (.project_id|type)=="string"
    and .hook=="skill-usage-audit" and (.source|type)=="string")' "$STORE" >/dev/null 2>&1
  assert_exit "second store: the row satisfies the store schema" 0 "$?"
else
  bad "second store not written (unconditional, no sink)"
fi

# --- The emitter's envelope, through the sink, is a conforming record --------
# The emitter produces envelopes, not records; the record shape is the sink's.
# Run the pair end to end so a row this plugin's own producer causes is
# asserted against the schema session-log-lib.sh documents, on both routes.
PROJE="$TEST_TMPDIR/emitter-record"
mkdir -p "$PROJE"
env HOOK_TELEMETRY_SINK="$HOOK_DIR/hook-telemetry-sink.sh" CLAUDE_PROJECT_DIR="$PROJE" \
  bash "$HOOK" <<<'{"session_id":"sess-e","hook_event_name":"PermissionDenied","tool_name":"Bash","tool_input":{"command":"git push --force"}}' >/dev/null 2>&1
REC_SCHEMA='(.ts|type)=="string" and (.hook_event_name|type)=="string"
  and (.status|type)=="string" and .source=="envelope"
  and ((.duration_ms|type)=="number" or .duration_ms==null)
  and (has("event")|not)
  and (.hook|type)=="string" and (.exit_code|type)=="number"
  and (.subject|type)=="string" and (.tool|type)=="string"'
SESSION_REC="$PROJE/.observability/claude/sessions/sess-e.jsonl"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -s "$SESSION_REC" ]] && break
  sleep 0.2
done
if [[ -s "$SESSION_REC" ]]; then
  jq -e -s "all(.[]; $REC_SCHEMA and (.session_id|type)==\"string\")" "$SESSION_REC" >/dev/null 2>&1
  assert_exit "emitter envelope → per-session record satisfies the schema" 0 "$?"
  assert_eq "emitter envelope → hook_event_name carried" "PermissionDenied" \
    "$(jq -r '.hook_event_name' "$SESSION_REC")"
else
  bad "emitter envelope → sink wrote no per-session record at $SESSION_REC"
fi

PROJEL="$TEST_TMPDIR/emitter-record-legacy"
mkdir -p "$PROJEL"
env HOOK_TELEMETRY_SINK="$HOOK_DIR/hook-telemetry-sink.sh" CLAUDE_PROJECT_DIR="$PROJEL" \
  bash "$HOOK" <<<'{"hook_event_name":"ConfigChange","source":"project_settings"}' >/dev/null 2>&1
LEGACY_REC="$PROJEL/.observability/claude/hook-events.jsonl"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -s "$LEGACY_REC" ]] && break
  sleep 0.2
done
if [[ -s "$LEGACY_REC" ]]; then
  jq -e -s "all(.[]; $REC_SCHEMA and (has(\"session_id\")|not))" "$LEGACY_REC" >/dev/null 2>&1
  assert_exit "emitter envelope with no session → shared-file record satisfies the schema" 0 "$?"
else
  bad "emitter envelope → sink wrote no shared-file record at $LEGACY_REC"
fi

# expansion_type is optional: recorded when present, never gated on.
PROJX="$TEST_TMPDIR/exp-noexp"
mkdir -p "$PROJX"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJX" \
  bash "$HOOK" <<<'{"hook_event_name":"UserPromptExpansion","command_name":"deploy"}' >/dev/null 2>&1
STOREX="$PROJX/.claude/observability/skill-usage.jsonl"
if [[ -s "$STOREX" ]]; then
  assert_eq "no-expansion_type skill" "deploy" "$(jq -r '.skill' "$STOREX")"
  assert_eq "no-expansion_type source" "expansion" "$(jq -r '.source' "$STOREX")"
  assert_eq "expansion_type key absent" "false" "$(jq -r 'has("expansion_type")' "$STOREX")"
else
  bad "second store not written when expansion_type is absent"
fi

PROJM="$TEST_TMPDIR/exp-mcp"
mkdir -p "$PROJM"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJM" \
  bash "$HOOK" <<<'{"hook_event_name":"UserPromptExpansion","command_name":"ask","expansion_type":"mcp_prompt"}' >/dev/null 2>&1
assert_eq "mcp_prompt recorded" "mcp_prompt" \
  "$(jq -r '.expansion_type' "$PROJM/.claude/observability/skill-usage.jsonl" 2>/dev/null)"

PROJ2="$TEST_TMPDIR/exp-dir"
mkdir -p "$PROJ2"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJ2" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR="telemetry/skills" \
  bash "$HOOK" <<<"$EXP" >/dev/null 2>&1
assert_eq "skill_usage_dir override used" "research" \
  "$(jq -r '.skill' "$PROJ2/telemetry/skills/skill-usage.jsonl" 2>/dev/null)"

# An invalid override is visible and cannot escape the project. CLAUDE_PLUGIN_DATA
# is isolated because the advisory goes through hook::notice_once, which persists
# a once-per-session marker there.
PROJB="$TEST_TMPDIR/exp-bad"
mkdir -p "$PROJB"
BADCFG_DATA="$TEST_TMPDIR/badcfg-data"
mkdir -p "$BADCFG_DATA"
INVALID_OUTPUT=$(env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJB" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR="../outside" \
  CLAUDE_PLUGIN_DATA="$BADCFG_DATA" \
  bash "$HOOK" <<<"$EXP" 2>/dev/null)
assert_file_absent "traversal override cannot write outside the project" \
  "$TEST_TMPDIR/outside/skill-usage.jsonl"
assert_contains "invalid override emits a visible advisory" "$INVALID_OUTPUT" \
  "claude-ops skipped skill-usage logging"
assert_eq "invalid override advisory uses the hook protocol" "UserPromptExpansion" \
  "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$INVALID_OUTPUT" 2>/dev/null)"
assert_contains "invalid override advisory is user-visible (systemMessage)" \
  "$(jq -r '.systemMessage // empty' <<<"$INVALID_OUTPUT" 2>/dev/null)" \
  "claude-ops skipped skill-usage logging"

PROJU="$TEST_TMPDIR/exp-user"
HOMEU="$TEST_TMPDIR/exp-home"
mkdir -p "$PROJU" "$HOMEU"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJU" HOME="$HOMEU" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE="user" \
  bash "$HOOK" <<<"$EXP" >/dev/null 2>&1
assert_eq "user scope writes under HOME" "research" \
  "$(jq -r '.skill' "$HOMEU/.claude/observability/skill-usage.jsonl" 2>/dev/null)"
assert_eq "user-scope row carries the project field" "exp-user" \
  "$(jq -r '.project' "$HOMEU/.claude/observability/skill-usage.jsonl" 2>/dev/null)"
assert_file_absent "user scope leaves the project tree untouched" \
  "$PROJU/.claude/observability/skill-usage.jsonl"

# The shared switch suppresses BOTH of this row's outputs.
PROJK="$TEST_TMPDIR/exp-killed"
mkdir -p "$PROJK"
expect_no_envelope "skill-expansion: kill switch → no envelope (again, with the store)" \
  "$HOOK" "$EXP" "$TEST_TMPDIR/exp-killed.json" \
  CLAUDE_PROJECT_DIR="$PROJK" CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED=false
assert_file_absent "skill-expansion: kill switch → no second store" \
  "$PROJK/.claude/observability/skill-usage.jsonl"

# A missing command_name skips both outputs.
PROJN="$TEST_TMPDIR/exp-nocmd"
mkdir -p "$PROJN"
expect_no_envelope "skill-expansion: no command_name → no envelope" \
  "$HOOK" '{"hook_event_name":"UserPromptExpansion","expansion_type":"slash_command"}' \
  "$TEST_TMPDIR/exp-nocmd.json" CLAUDE_PROJECT_DIR="$PROJN"
assert_file_absent "skill-expansion: no command_name → no second store" \
  "$PROJN/.claude/observability/skill-usage.jsonl"

# --- Every switch off: the emitter leaves before parsing the library --------
PROJA="$TEST_TMPDIR/all-off"
mkdir -p "$PROJA"
expect_no_envelope "all switches off → no envelope" \
  "$HOOK" "$EXP" "$TEST_TMPDIR/all-off.json" CLAUDE_PROJECT_DIR="$PROJA" \
  CLAUDE_PLUGIN_OPTION_API_ERROR_AUDIT_ENABLED=false \
  CLAUDE_PLUGIN_OPTION_CONFIG_CHANGE_AUDIT_ENABLED=false \
  CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_ENABLED=false \
  CLAUDE_PLUGIN_OPTION_PERMISSION_DENIED_AUDIT_ENABLED=false \
  CLAUDE_PLUGIN_OPTION_PRE_COMPACT_AUDIT_ENABLED=false \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED=false \
  CLAUDE_PLUGIN_OPTION_TOOL_FAILURE_AUDIT_ENABLED=false
assert_file_absent "all switches off → no second store" \
  "$PROJA/.claude/observability/skill-usage.jsonl"

report
