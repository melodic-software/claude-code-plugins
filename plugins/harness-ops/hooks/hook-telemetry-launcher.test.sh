#!/usr/bin/env bash
# Contract test for hook-telemetry-launcher.sh (harness-ops plugin). Black-box.
# At session start the script writes <root>/hook-telemetry-sink.sh, which execs
# the plugin's own hook-telemetry-sink.sh, when HOOK_TELEMETRY_SINK names that
# path relative to the project, and nothing otherwise. The cases then pipe an
# envelope through the launcher the way a producer does, so the whole route
# from a relative HOOK_TELEMETRY_SINK to a written row is checked.
# test-scope: plugins/harness-ops/hooks/hooks.json plugins/harness-ops/hooks/hook-telemetry-sink.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HOOK_DIR/hook-telemetry-launcher.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=harness-ops-test-helpers.sh
source "$HOOK_DIR/harness-ops-test-helpers.sh"

ROOT_REL=".observability/claude"
WIRED="$ROOT_REL/hook-telemetry-sink.sh"

# run_launcher <project> <HOOK_TELEMETRY_SINK value> [VAR=value...]
run_launcher() {
  local proj="$1" sink="$2"
  shift 2
  env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR -u CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES \
    CLAUDE_PROJECT_DIR="$proj" HOOK_TELEMETRY_SINK="$sink" "$@" bash "$SCRIPT" </dev/null
}

# send <project> <launcher>: one {tool, file} envelope through the launcher, run
# as a producer runs it: by path, with none of this plugin's options set.
send() {
  jq -nc '{schema_version:"1.1", timestamp:"2026-07-12T00:00:00Z", hook:"bash-format",
    hook_event:"PostToolUse", status:"ok", duration_ms:7, data:{tool:"Write", file:"a.sh"}}' |
    env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR -u CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES \
      CLAUDE_PROJECT_DIR="$1" "$2" >/dev/null 2>&1
}

# --- wired: the launcher is written, executable, guarded and reaches the sink -
P="$TEST_TMPDIR/p1"
mkdir -p "$P/.git"
OUT="$(run_launcher "$P" "$WIRED" 2>&1)"
RC=$?
assert_exit "wired: exit 0" 0 "$RC"
assert_silent "wired: no output" "$OUT"
L="$P/$WIRED"
if [[ -x "$L" ]]; then
  ok "wired: the launcher is written and executable"
  printf -v want_target '%q' "$(cd -P "$HOOK_DIR" && pwd)/hook-telemetry-sink.sh"
  assert_contains "wired: it execs the plugin's sink" "$(cat "$L")" "$want_target"
  assert_eq "wired: the root carries its self-ignoring guard" "*" "$(head -1 "$P/$ROOT_REL/.gitignore")"
  send "$P" "$L"
  assert_eq "wired: an envelope through the launcher lands one row" 1 "$(wc -l <"$P/$ROOT_REL/hook-events.jsonl" 2>/dev/null | tr -d ' ')"
  assert_eq "wired: the row's subject comes from data.file" "a.sh" "$(jq -r '.subject' "$P/$ROOT_REL/hook-events.jsonl" 2>/dev/null)"
else
  bad "wired: no executable launcher at $L"
fi

# --- a second run leaves an unchanged launcher alone, and restores an edited one
before="$(cat "$L" 2>/dev/null)"
touch -t 200001010000 "$L"
touch "$TEST_TMPDIR/ref"
run_launcher "$P" "./$WIRED"
if [[ "$L" -ot "$TEST_TMPDIR/ref" ]]; then
  ok "rerun with a ./ spelling: an unchanged launcher is not rewritten"
else
  bad "rerun with a ./ spelling: the unchanged launcher was rewritten"
fi
printf '#!/usr/bin/env bash\nexit 0\n' >"$L"
run_launcher "$P" "$WIRED"
assert_eq "an edited launcher is rewritten" "$before" "$(cat "$L" 2>/dev/null)"
assert_eq "no temporary file is left behind" 0 "$(find "$P/$ROOT_REL" -name 'hook-telemetry-sink.sh.*' | wc -l | tr -d ' ')"

# --- a session started in a subdirectory writes under the repository root -------
# A real repository, so git resolves the root the way the sink and producers do.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
PS="$TEST_TMPDIR/ps"
mkdir -p "$PS/sub"
if git init -q "$PS" 2>/dev/null; then
  run_launcher "$PS/sub" "$WIRED"
  if [[ -x "$PS/$WIRED" ]]; then
    ok "subdirectory session: the launcher is under the repository root"
  else
    bad "subdirectory session: no launcher at $PS/$WIRED"
  fi
  assert_file_absent "subdirectory session: nothing under the subdirectory" "$PS/sub/$ROOT_REL"
else
  bad "subdirectory session: git init failed"
fi

# --- not wired to the launcher: no file ------------------------------------------
P2="$TEST_TMPDIR/p2"
mkdir -p "$P2/.git"
run_launcher "$P2" ""
assert_file_absent "no HOOK_TELEMETRY_SINK: no launcher" "$P2/$WIRED"
assert_file_absent "no HOOK_TELEMETRY_SINK: no log root" "$P2/$ROOT_REL"
run_launcher "$P2" ".claude/hooks/hook-telemetry-sink.sh"
assert_file_absent "a sink of the repository's own: no launcher" "$P2/$WIRED"
run_launcher "$P2" "/opt/sink.sh"
assert_file_absent "an absolute sink: no launcher" "$P2/$WIRED"

# --- an operator's guard refuses the write ---------------------------------------
P3="$TEST_TMPDIR/p3"
mkdir -p "$P3/.git" "$P3/$ROOT_REL"
printf 'sessions/\n' >"$P3/$ROOT_REL/.gitignore"
run_launcher "$P3" "$WIRED"
assert_file_absent "checkout with an operator's guard: no launcher" "$P3/$WIRED"

# --- a configured root: the launcher lives there and carries the options ---------
P4="$TEST_TMPDIR/p4"
mkdir -p "$P4"
run_launcher "$P4" "telemetry/claude/hook-telemetry-sink.sh" \
  CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=telemetry/claude CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES=5000
L4="$P4/telemetry/claude/hook-telemetry-sink.sh"
if [[ -x "$L4" ]]; then
  ok "configured root: the launcher is written under it"
  assert_contains "configured root: the byte cap is carried" "$(cat "$L4")" "CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES=5000"
  send "$P4" "$L4"
  assert_eq "configured root: a producer without the option still writes under it" 1 "$(wc -l <"$P4/telemetry/claude/hook-events.jsonl" 2>/dev/null | tr -d ' ')"
  assert_file_absent "configured root: nothing under the default root" "$P4/$ROOT_REL"
else
  bad "configured root: no executable launcher at $L4"
fi
run_launcher "$P4" "$WIRED" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=telemetry/claude
assert_file_absent "configured root: the default path is not the launcher" "$P4/$WIRED"
run_launcher "$P4" "../up/hook-telemetry-sink.sh" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=../up
assert_file_absent "an uncontained root writes nothing" "$TEST_TMPDIR/up"

report
