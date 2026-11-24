#!/usr/bin/env bash
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/refresh-sink-launcher.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=session-telemetry-test-helpers.sh
source "$HOOK_DIR/session-telemetry-test-helpers.sh"

ROOT="$TEST_TMPDIR/plugin root's v1"
mkdir -p "$ROOT/hooks"
cp "$HOOK_DIR/hook-telemetry-sink.sh" "$HOOK_DIR/hook-utils.sh" "$HOOK_DIR/session-log-lib.sh" "$ROOT/hooks/"
DATA="$TEST_TMPDIR/cfg/plugins/data/session-telemetry-mkt"
LAUNCHER="$DATA/hook-telemetry-sink.sh"

refresh() {
  env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR -u CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES \
    CLAUDE_PLUGIN_DATA="$DATA" CLAUDE_PLUGIN_ROOT="$ROOT" "$@" bash "$HOOK" </dev/null 2>&1
}

envelope() {
  printf '{"schema_version":"1.1","timestamp":"2026-11-08T00:00:00Z","hook":"%s","hook_event":"PostToolUse","status":"ok","duration_ms":3,"data":{"tool":"Write","file":"a.sh"}}' "$1"
}

OUT=$(refresh)
assert_exit "first refresh exits 0" 0 "$?"
assert_silent "first refresh prints nothing (SessionStart stdout is context)" "$OUT"
if [[ -x "$LAUNCHER" && -f "$LAUNCHER" ]]; then ok "launcher written and executable"; else bad "no executable launcher at $LAUNCHER"; fi

P1="$TEST_TMPDIR/p1"
mkdir -p "$P1"
envelope e2e | env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR CLAUDE_PROJECT_DIR="$P1" "$LAUNCHER" >/dev/null 2>&1
assert_eq "launcher → sink: one row in the default root" 1 "$(wc -l <"$P1/.observability/claude/hook-events.jsonl" 2>/dev/null | tr -d ' ')"
assert_eq "launcher → sink: subject from data.file" "a.sh" "$(jq -r .subject "$P1/.observability/claude/hook-events.jsonl" 2>/dev/null)"

ln "$LAUNCHER" "$TEST_TMPDIR/keep"
refresh >/dev/null
if [[ "$LAUNCHER" -ef "$TEST_TMPDIR/keep" ]]; then ok "an unchanged launcher is left in place"; else bad "an unchanged launcher was rewritten"; fi

touch -t 200001010000 "$LAUNCHER"
: >"$TEST_TMPDIR/before-refresh"
touch -t 200101010000 "$TEST_TMPDIR/before-refresh"
refresh >/dev/null
if [[ "$LAUNCHER" -nt "$TEST_TMPDIR/before-refresh" ]]; then ok "an unchanged launcher's mtime is refreshed"; else bad "an unchanged launcher kept its old mtime"; fi
if [[ "$LAUNCHER" -ef "$TEST_TMPDIR/keep" ]]; then ok "the touch does not rewrite the launcher"; else bad "the touch rewrote the launcher"; fi

ROOT2="$TEST_TMPDIR/plugin-v2"
cp -r "$ROOT" "$ROOT2"
refresh CLAUDE_PLUGIN_ROOT="$ROOT2" >/dev/null
if [[ "$LAUNCHER" -ef "$TEST_TMPDIR/keep" ]]; then bad "a moved root left the old launcher"; else ok "a moved root rewrites the launcher"; fi
assert_contains "the rewritten launcher names the new root" "$(cat "$LAUNCHER")" "$ROOT2/hooks/hook-telemetry-sink.sh"

refresh CLAUDE_PLUGIN_ROOT="$ROOT2" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=telemetry/claude >/dev/null
P2="$TEST_TMPDIR/p2"
mkdir -p "$P2"
envelope opt | env CLAUDE_PROJECT_DIR="$P2" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=foreign/dir "$LAUNCHER" >/dev/null 2>&1
assert_eq "configured log dir carried to the sink" 1 "$(wc -l <"$P2/telemetry/claude/hook-events.jsonl" 2>/dev/null | tr -d ' ')"
assert_file_absent "the caller's same-named option does not win" "$P2/foreign"
refresh CLAUDE_PLUGIN_ROOT="$ROOT2" >/dev/null
P3="$TEST_TMPDIR/p3"
mkdir -p "$P3"
envelope unset | env CLAUDE_PROJECT_DIR="$P3" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=foreign/dir "$LAUNCHER" >/dev/null 2>&1
assert_eq "no option set: the sink's default root, not the caller's" 1 "$(wc -l <"$P3/.observability/claude/hook-events.jsonl" 2>/dev/null | tr -d ' ')"

rm -rf "$ROOT2"
envelope stale | "$LAUNCHER" >/dev/null 2>&1
assert_exit "a launcher whose sink is gone exits 0" 0 "$?"
assert_file_absent "a launcher whose sink is gone removes itself" "$LAUNCHER"

DATA_NONE="$TEST_TMPDIR/none"
OUT=$(env -u CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA="$DATA_NONE" bash "$HOOK" </dev/null 2>&1)
assert_silent "no CLAUDE_PLUGIN_ROOT: silent" "$OUT"
assert_file_absent "no CLAUDE_PLUGIN_ROOT: no launcher" "$DATA_NONE"
OUT=$(env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" </dev/null 2>&1)
assert_silent "no CLAUDE_PLUGIN_DATA: silent" "$OUT"
OUT=$(env CLAUDE_PLUGIN_DATA="$DATA_NONE" CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/no-root" bash "$HOOK" </dev/null 2>&1)
assert_file_absent "a root with no sink: no launcher" "$DATA_NONE/hook-telemetry-sink.sh"

printf 'precious\n' >"$TEST_TMPDIR/precious"
rm -f "$LAUNCHER"
ln -s "$TEST_TMPDIR/precious" "$LAUNCHER"
refresh >/dev/null
assert_eq "the symlink's target is untouched" "precious" "$(cat "$TEST_TMPDIR/precious")"
if [[ -f "$LAUNCHER" && ! -L "$LAUNCHER" ]]; then ok "the symlink is replaced by a launcher"; else bad "the symlink was kept"; fi

DATA_DIR="$TEST_TMPDIR/dirdata"
mkdir -p "$DATA_DIR/hook-telemetry-sink.sh"
OUT=$(env CLAUDE_PLUGIN_DATA="$DATA_DIR" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" </dev/null 2>&1)
assert_exit "a directory at the launcher path: exit 0" 0 "$?"
assert_eq "a directory at the launcher path: nothing written inside it" "" "$(ls -A "$DATA_DIR/hook-telemetry-sink.sh")"

DATA_OPT="$TEST_TMPDIR/optdata"
OPTS="$DATA_OPT/options.json"
env -u CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES CLAUDE_PLUGIN_DATA="$DATA_OPT" CLAUDE_PLUGIN_ROOT="$ROOT" \
  CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR='tele"m\etry/hooks' CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE=user \
  bash "$HOOK" </dev/null >/dev/null 2>&1
assert_eq "options.json: a value with a quote and a backslash round-trips" 'tele"m\etry/hooks' \
  "$(jq -r '.options.session_event_log_dir' "$OPTS" 2>/dev/null)"
assert_eq "options.json: each option is keyed by its lower-case name" "user" \
  "$(jq -r '.options.skill_usage_scope' "$OPTS" 2>/dev/null)"
assert_eq "options.json: an option the hooks did not get is absent" "false" \
  "$(jq '.options | has("hook_events_max_bytes")' "$OPTS" 2>/dev/null)"
assert_eq "options.json: names the plugin root the hooks ran from" "$ROOT" \
  "$(jq -r '.plugin_root' "$OPTS" 2>/dev/null)"
env -u CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES -u CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE CLAUDE_PLUGIN_DATA="$DATA_OPT" \
  CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=telemetry bash "$HOOK" </dev/null >/dev/null 2>&1
assert_eq "options.json: rewritten when the options change" "telemetry false" \
  "$(jq -r '"\(.options.session_event_log_dir) \(.options | has("skill_usage_scope"))"' "$OPTS" 2>/dev/null)"

report
