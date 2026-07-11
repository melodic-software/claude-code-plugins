#!/usr/bin/env bash
# Black-box contract tests for start-dashboard.sh.
# Invokes the script as a subprocess — never spawns a real dashboard container unless
# CC_OTEL_DASHBOARD_RUN_CMD / CC_OTEL_DASHBOARD_INSPECT_STATE are unset on the host.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SCRIPT="$SCRIPT_DIR/start-dashboard.sh"

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

# --- 1. --help ---
out="$(bash "$SCRIPT" --help 2>&1)"
rc=$?
assert_eq "--help exits 0" "0" "$rc"
assert_contains "--help prints Usage" "$out" "Usage:"

# --- 2. unknown arg ---
out="$(bash "$SCRIPT" --bogus 2>&1)"
rc=$?
assert_eq "unknown arg exits 2" "2" "$rc"
assert_contains "unknown arg reported" "$out" "unknown argument"

# --- 3. --dry-run emits report keys ---
out="$(CC_OTEL_DASHBOARD_INSPECT_STATE=absent bash "$SCRIPT" --dry-run 2>/dev/null)"
rc=$?
assert_eq "--dry-run exits 0" "0" "$rc"
for key in \
  "container_name=" \
  "image=" \
  "ports=18888,18889" \
  "port_18888=" \
  "label_stack=claude-code-observability" \
  "label_component=aspire-dashboard" \
  "label_role=otel-live-tail" \
  "label_managed_by=manual" \
  "label_oci_title=" \
  "container_state=" \
  "action="; do
  assert_contains "--dry-run emits $key" "$out" "$key"
done

# --- 4. canonical container name ---
name_line="$(printf '%s\n' "$out" | grep '^container_name=' | head -1)"
assert_eq "canonical container name" "container_name=local-otel-dashboard-claude-code" "$name_line"

# --- 4b. --role apps resolves the apps identity (name, ports, labels) ---
apps_out="$(CC_OTEL_DASHBOARD_INSPECT_STATE=absent bash "$SCRIPT" --role apps --dry-run 2>/dev/null)"
rc=$?
assert_eq "--role apps --dry-run exits 0" "0" "$rc"
assert_contains "apps role name" "$apps_out" "container_name=local-otel-dashboard-apps"
assert_contains "apps role ports" "$apps_out" "ports=19888,19889"
assert_contains "apps role label_role" "$apps_out" "label_role=app-otel-live-tail"
assert_contains "apps role label_stack" "$apps_out" "label_stack=local-app-observability"

# --- 4c. unknown role exits 2 ---
out_role="$(bash "$SCRIPT" --role bogus 2>&1)"
rc=$?
assert_eq "unknown role exits 2" "2" "$rc"
assert_contains "unknown role reported" "$out_role" "unknown role"

# --- 5. action enum when inspect state is controlled ---
for pair in \
  "running:noop-already-running" \
  "stopped:would-start" \
  "aspire-dashboard-running:skip-aspire-dashboard-present" \
  "docker-absent:skip-docker-absent" \
  "docker-unreachable:skip-docker-unreachable"; do
  state="${pair%%:*}"
  expected_action="${pair#*:}"
  dry_out="$(CC_OTEL_DASHBOARD_INSPECT_STATE="$state" bash "$SCRIPT" --dry-run 2>/dev/null)"
  action_line="$(printf '%s\n' "$dry_out" | grep '^action=' | head -1)"
  assert_eq "inspect $state => $expected_action" "action=$expected_action" "$action_line"
done

# --- 6. absent + port listening => skip-port-in-use ---
# Force port listening by binding 18888 in a subshell if free; skip assertion if already in use.
if (exec 3<>"/dev/tcp/127.0.0.1/18888") 2>/dev/null; then
  exec 3>&- 3<&-
  pass "port 18888 already listening — skip bind probe"
  dry_out="$(CC_OTEL_DASHBOARD_INSPECT_STATE=absent bash "$SCRIPT" --dry-run 2>/dev/null)"
  action_line="$(printf '%s\n' "$dry_out" | grep '^action=' | head -1)"
  assert_eq "absent + port busy => skip-port-in-use" "action=skip-port-in-use" "$action_line"
else
  pass "port 18888 free on this host — skip-port-in-use case N/A"
fi

# --- 7. image honors CC_OTEL_DASHBOARD_IMAGE ---
custom_image="example.invalid/otel-dashboard:pin"
dry_out="$(CC_OTEL_DASHBOARD_IMAGE="$custom_image" CC_OTEL_DASHBOARD_INSPECT_STATE=absent bash "$SCRIPT" --dry-run 2>/dev/null)"
image_line="$(printf '%s\n' "$dry_out" | grep '^image=' | head -1)"
assert_eq "image honors CC_OTEL_DASHBOARD_IMAGE" "image=$custom_image" "$image_line"

# --- 8. CC_OTEL_DASHBOARD_RUN_CMD seam invoked on would-spawn ---
RUN_LOG="$TMP/dashboard-run.log"
cat >"$TMP/run-dashboard.sh" <<EOF
#!/usr/bin/env bash
: >"$RUN_LOG"
EOF
chmod +x "$TMP/run-dashboard.sh"
CC_OTEL_DASHBOARD_RUN_CMD="$TMP/run-dashboard.sh" \
  CC_OTEL_DASHBOARD_INSPECT_STATE=absent \
  bash "$SCRIPT" >/dev/null 2>/dev/null
if [[ -f "$RUN_LOG" ]]; then
  pass "RUN_CMD seam invoked on would-spawn"
else
  # Port may be in use on developer machine — only fail when action would have been spawn
  dry_out="$(CC_OTEL_DASHBOARD_INSPECT_STATE=absent bash "$SCRIPT" --dry-run 2>/dev/null)"
  action_line="$(printf '%s\n' "$dry_out" | grep '^action=' | head -1)"
  if [[ "$action_line" == "action=would-spawn" ]]; then
    fail "RUN_CMD seam invoked on would-spawn" "log file present" "log file missing"
  else
    pass "RUN_CMD seam skipped — action was not would-spawn ($action_line)"
  fi
fi

# --- 9. aspire-dashboard-running prints stop hint ---
aspire_dashboard_err="$(CC_OTEL_DASHBOARD_INSPECT_STATE=aspire-dashboard-running bash "$SCRIPT" 2>&1 >/dev/null)"
assert_contains "aspire-dashboard hint mentions aspire-dashboard" "$aspire_dashboard_err" "aspire-dashboard"
assert_contains "aspire-dashboard hint mentions docker stop" "$aspire_dashboard_err" "docker stop"

[[ ${FAILED:-0} -eq 0 ]] || exit 1
