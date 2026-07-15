#!/usr/bin/env bash
# Black-box contract tests for start-collector.sh.
# Invokes the script as a subprocess and asserts on stdout/stderr/exit — never spawns a real
# Collector (the live down->revive->up path is exercised by the Phase 1 Sanity Check, not here).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SCRIPT="$SCRIPT_DIR/start-collector.sh"

# Inline test helpers — self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"; }
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
skip_case() { printf 'SKIP: %s\n' "$1" >&2; }
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_exit() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_file_exists() { if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "file exists: $2" "absent"; fi; }
FAILED=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. --help: exit 0, prints usage ---
out="$(bash "$SCRIPT" --help 2>&1)"
rc=$?
assert_eq "--help exits 0" "0" "$rc"
assert_contains "--help prints Usage" "$out" "Usage:"

# --- 2. unknown arg: exit 2, reports it ---
out="$(bash "$SCRIPT" --bogus 2>&1)"
rc=$?
assert_eq "unknown arg exits 2" "2" "$rc"
assert_contains "unknown arg reported" "$out" "unknown argument"

# --- 3. --dry-run emits all report keys, exit 0 ---
out="$(bash "$SCRIPT" --dry-run 2>/dev/null)"
rc=$?
assert_eq "--dry-run exits 0" "0" "$rc"
for key in "store_dir=" "config=" "binary=" "port_4318=" "port_4317=" "action="; do
  assert_contains "--dry-run emits $key" "$out" "$key"
done

# --- 4. action= is a valid enum value (live :4318/:4317 state varies) ---
action_line="$(printf '%s\n' "$out" | grep '^action=' | head -1)"
case "$action_line" in
  action=noop-already-running | action=skip-binary-absent | action=would-spawn | action=skip-prune-in-progress | action=skip-grpc-port-in-use | action=skip-port-conflict)
    pass "action= is a valid enum"
    ;;
  *) fail "action= is a valid enum" "valid enum value" "$action_line" ;;
esac

# --- 5. store_dir defaults to .claude/observability/otel when CC_OTEL_STORE unset ---
unset_store_out="$(env -u CC_OTEL_STORE bash "$SCRIPT" --dry-run 2>/dev/null)"
store_line="$(printf '%s\n' "$unset_store_out" | grep '^store_dir=' | head -1)"
case "$store_line" in
  store_dir=*/.claude/observability/otel) pass "store_dir default ends with .claude/observability/otel" ;;
  *) fail "store_dir default ends with .claude/observability/otel" \
    "store_dir=*/.claude/observability/otel" "$store_line" ;;
esac

# --- 6. store_dir == CC_OTEL_STORE when set ---
out="$(CC_OTEL_STORE="$TMP/pinned-store" bash "$SCRIPT" --dry-run 2>/dev/null)"
store_line="$(printf '%s\n' "$out" | grep '^store_dir=' | head -1)"
assert_eq "store_dir honors CC_OTEL_STORE" "store_dir=$TMP/pinned-store" "$store_line"

# --- 7. binary resolution honors CC_OTEL_BIN override (precedence over PATH/probe) ---
FAKEBIN="$TMP/otelcol-contrib"
printf '#!/bin/sh\n' >"$FAKEBIN"
chmod +x "$FAKEBIN"
out="$(CC_OTEL_BIN="$FAKEBIN" bash "$SCRIPT" --dry-run 2>/dev/null)"
bin_line="$(printf '%s\n' "$out" | grep '^binary=' | head -1)"
assert_eq "binary honors CC_OTEL_BIN" "binary=$FAKEBIN" "$bin_line"

# --- 8. binary=NOT_FOUND when unresolvable (HOME without ~/.otelcol, no CC_OTEL_BIN; PATH kept
#        intact so the script's own coreutils — dirname/git/tr — still work. Relies on
#        otelcol-contrib NOT being on PATH, which is the repo's documented install layout). ---
out="$(env -u CC_OTEL_BIN HOME="$TMP/empty-home" bash "$SCRIPT" --dry-run 2>/dev/null)"
bin_line="$(printf '%s\n' "$out" | grep '^binary=' | head -1)"
assert_eq "binary=NOT_FOUND when unresolvable" "binary=NOT_FOUND" "$bin_line"

# --- 9. prune sentinel (.prune-in-progress dir) suppresses spawn (revival-race guard) ---
PRUNE_STORE="$TMP/prune-store"
mkdir -p "$PRUNE_STORE/.prune-in-progress"
out="$(CC_OTEL_STORE="$PRUNE_STORE" bash "$SCRIPT" --dry-run 2>/dev/null)"
action_line="$(printf '%s\n' "$out" | grep '^action=' | head -1)"
assert_eq "sentinel present => skip-prune-in-progress" "action=skip-prune-in-progress" "$action_line"

[[ ${FAILED:-0} -eq 0 ]] || exit 1
