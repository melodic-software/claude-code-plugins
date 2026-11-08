#!/usr/bin/env bash
# Contract test for refresh-sink-launcher.sh (harness-ops plugin). Black-box.
# The SessionStart hook keeps ${CLAUDE_PLUGIN_DATA}/hook-telemetry-sink.sh, a
# launcher for this install's sink, which HOOK_TELEMETRY_SINK=@harness-ops
# resolves to (docs/contracts/hook-telemetry "Sink path resolution").
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/refresh-sink-launcher.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=harness-ops-test-helpers.sh
source "$HOOK_DIR/harness-ops-test-helpers.sh"

# A plugin root whose path carries a space and a quote, holding the files the
# sink needs, so the launcher's quoting and the sink's sibling sourcing are
# both exercised.
ROOT="$TEST_TMPDIR/plugin root's v1"
mkdir -p "$ROOT/hooks"
cp "$HOOK_DIR/hook-telemetry-sink.sh" "$HOOK_DIR/hook-utils.sh" "$HOOK_DIR/session-log-lib.sh" "$ROOT/hooks/"
DATA="$TEST_TMPDIR/cfg/plugins/data/harness-ops-mkt"
LAUNCHER="$DATA/hook-telemetry-sink.sh"

# refresh [env assignments...] → run the hook as SessionStart does; prints its output.
refresh() {
  env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR -u CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES \
    CLAUDE_PLUGIN_DATA="$DATA" CLAUDE_PLUGIN_ROOT="$ROOT" "$@" bash "$HOOK" </dev/null 2>&1
}

envelope() {
  printf '{"schema_version":"1.1","timestamp":"2026-11-08T00:00:00Z","hook":"%s","hook_event":"PostToolUse","status":"ok","duration_ms":3,"data":{"tool":"Write","file":"a.sh"}}' "$1"
}

# --- writes an executable launcher, silently -----------------------------------
OUT=$(refresh)
assert_exit "first refresh exits 0" 0 "$?"
assert_silent "first refresh prints nothing (SessionStart stdout is context)" "$OUT"
if [[ -x "$LAUNCHER" && -f "$LAUNCHER" ]]; then ok "launcher written and executable"; else bad "no executable launcher at $LAUNCHER"; fi

# --- the launcher reaches the installed sink -----------------------------------
P1="$TEST_TMPDIR/p1"
mkdir -p "$P1"
envelope e2e | env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR CLAUDE_PROJECT_DIR="$P1" "$LAUNCHER" >/dev/null 2>&1
assert_eq "launcher → sink: one row in the default root" 1 "$(wc -l <"$P1/.observability/claude/hook-events.jsonl" 2>/dev/null | tr -d ' ')"
assert_eq "launcher → sink: subject from data.file" "a.sh" "$(jq -r .subject "$P1/.observability/claude/hook-events.jsonl" 2>/dev/null)"

# --- unchanged content is not rewritten ----------------------------------------
ln "$LAUNCHER" "$TEST_TMPDIR/keep"
refresh >/dev/null
if [[ "$LAUNCHER" -ef "$TEST_TMPDIR/keep" ]]; then ok "an unchanged launcher is left in place"; else bad "an unchanged launcher was rewritten"; fi

# --- a moved root rewrites it ---------------------------------------------------
ROOT2="$TEST_TMPDIR/plugin-v2"
cp -r "$ROOT" "$ROOT2"
refresh CLAUDE_PLUGIN_ROOT="$ROOT2" >/dev/null
if [[ "$LAUNCHER" -ef "$TEST_TMPDIR/keep" ]]; then bad "a moved root left the old launcher"; else ok "a moved root rewrites the launcher"; fi
assert_contains "the rewritten launcher names the new root" "$(cat "$LAUNCHER")" "$ROOT2/hooks/hook-telemetry-sink.sh"

# --- the install's sink options are carried; a caller's own are overridden -----
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

# --- a stale launcher removes itself -------------------------------------------
rm -rf "$ROOT2"
envelope stale | "$LAUNCHER" >/dev/null 2>&1
assert_exit "a launcher whose sink is gone exits 0" 0 "$?"
assert_file_absent "a launcher whose sink is gone removes itself" "$LAUNCHER"

# --- missing inputs: nothing written --------------------------------------------
DATA_NONE="$TEST_TMPDIR/none"
OUT=$(env -u CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA="$DATA_NONE" bash "$HOOK" </dev/null 2>&1)
assert_silent "no CLAUDE_PLUGIN_ROOT: silent" "$OUT"
assert_file_absent "no CLAUDE_PLUGIN_ROOT: no launcher" "$DATA_NONE"
OUT=$(env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" </dev/null 2>&1)
assert_silent "no CLAUDE_PLUGIN_DATA: silent" "$OUT"
OUT=$(env CLAUDE_PLUGIN_DATA="$DATA_NONE" CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/no-root" bash "$HOOK" </dev/null 2>&1)
assert_file_absent "a root with no sink: no launcher" "$DATA_NONE/hook-telemetry-sink.sh"

# --- a symlink at the launcher path is replaced, never followed -----------------
printf 'precious\n' >"$TEST_TMPDIR/precious"
rm -f "$LAUNCHER"
ln -s "$TEST_TMPDIR/precious" "$LAUNCHER"
refresh >/dev/null
assert_eq "the symlink's target is untouched" "precious" "$(cat "$TEST_TMPDIR/precious")"
if [[ -f "$LAUNCHER" && ! -L "$LAUNCHER" ]]; then ok "the symlink is replaced by a launcher"; else bad "the symlink was kept"; fi

# --- a directory at the launcher path is left alone -----------------------------
DATA_DIR="$TEST_TMPDIR/dirdata"
mkdir -p "$DATA_DIR/hook-telemetry-sink.sh"
OUT=$(env CLAUDE_PLUGIN_DATA="$DATA_DIR" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" </dev/null 2>&1)
assert_exit "a directory at the launcher path: exit 0" 0 "$?"
assert_eq "a directory at the launcher path: nothing written inside it" "" "$(ls -A "$DATA_DIR/hook-telemetry-sink.sh")"

report
