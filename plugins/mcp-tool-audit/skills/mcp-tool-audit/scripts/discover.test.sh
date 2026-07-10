#!/usr/bin/env bash
# Self-contained tests for discover.sh (no external test lib — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER="$SCRIPT_DIR/discover.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE=0

pass() {
  CASE=$((CASE + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE=$((CASE + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected to contain: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "$3" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    CASE=$((CASE + 1))
    FAILED=$((FAILED + 1))
    printf 'FAIL: %s\n  expected exit %s, got %s\n' "$1" "$2" "$3" >&2
  fi
}

# --- Build a fixture project with one TS, one Python, and one .NET server. ---
proj="$TEST_TMPDIR/proj"
mkdir -p "$proj/payments/node/src" "$proj/reports/python" "$proj/inventory/dotnet"
git -C "$proj" init -q
git -C "$proj" config user.email t@t.t
git -C "$proj" config user.name t

cat >"$proj/payments/node/src/server.ts" <<'TS'
server.registerTool(
  "payments_charge_card",
  { description: "Charge a card." },
  async () => ({})
);
TS

cat >"$proj/reports/python/server.py" <<'PY'
@mcp.tool
def get_report(report_id: str) -> str:
    """Get a report."""
    return ""
PY

cat >"$proj/inventory/dotnet/Tools.cs" <<'CS'
[McpServerTool]
public string ListItems(string boardId) => "";
CS

# --- Cases ---
assert_exit "--help exits 0" 0 "$(
  bash "$DISCOVER" --help >/dev/null 2>&1
  echo $?
)"

out="$(bash "$DISCOVER" --path "$proj")"
assert_contains "server count present" "$out" "Server count:"
assert_contains "typescript tool discovered" "$out" "Tool: payments_charge_card"
assert_contains "python tool discovered" "$out" "Tool: get_report"
assert_contains "dotnet tool discovered" "$out" "Tool: ListItems"
assert_contains "server label derived (payments)" "$out" "Server: payments"
assert_contains "runtime tagged (python)" "$out" "Runtime: python"

scoped="$(bash "$DISCOVER" --path "$proj/reports")"
assert_contains "scoped run finds in-scope tool" "$scoped" "Tool: get_report"
case "$scoped" in
  *payments_charge_card*) fail "scoped run excludes out-of-scope tool" "no payments_charge_card" ;;
  *) pass "scoped run excludes out-of-scope tool" ;;
esac

assert_exit "unknown arg exits 2" 2 "$(
  bash "$DISCOVER" --unknown 2>/dev/null
  echo $?
)"
assert_exit "--path without value exits 2" 2 "$(
  bash "$DISCOVER" --path 2>/dev/null
  echo $?
)"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE" >&2
exit 1
