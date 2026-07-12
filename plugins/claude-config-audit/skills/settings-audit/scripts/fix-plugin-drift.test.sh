#!/usr/bin/env bash
# Black-box contract tests for fix-plugin-drift.sh (self-contained — ships with the plugin).
# Uses --input <findings.json> to bypass the internal check invocation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fix-plugin-drift.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to contain: $3" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

make_case() {
  local case_dir="$TEST_TMPDIR/case-$CASE_NUM"
  mkdir -p "$case_dir"
  echo "$case_dir"
}

run_fix_dry() {
  local case_dir="$1"
  NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
    bash "$SCRIPT" --input "$case_dir/findings.json" 2>&1
}

run_fix_apply() {
  local case_dir="$1"
  NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
    bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1
}

# --- Case 1: no drift → no-op ---------------------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
echo '[{"key":"market1","status":"ok","skip_reason":"","orphans":[],"new_upstream":[],"renames":[]}]' >"$case_dir/findings.json"
echo '{"enabledPlugins":{"alpha@market1":true}}' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_dry "$case_dir") || exit_code=$?

assert_exit "case-1: no-op exit 0" 0 "$exit_code"
assert_contains "case-1: nothing-to-do msg" "$out" "No drift detected"

# --- Case 2: dry-run lists removals + adds without writing ------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}
EOF

out=$(run_fix_dry "$case_dir") || true

assert_contains "case-2: AUTO-REMOVE shown" "$out" "AUTO-REMOVE"
assert_contains "case-2: AUTO-ADD shown" "$out" "AUTO-ADD"
assert_contains "case-2: removed listed" "$out" "removed@market1"
assert_contains "case-2: newcomer listed" "$out" "newcomer@market1"
assert_contains "case-2: dry-run notice" "$out" "Dry-run only"

# Settings.json untouched in dry-run
unchanged=$(jq -e '.enabledPlugins["removed@market1"] == false' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-2: settings.json unchanged" "yes" "$unchanged"

# --- Case 3: --yes applies removal + addition atomically --------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}
EOF

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?

assert_exit "case-3: apply exit 0" 0 "$exit_code"
assert_contains "case-3: applied msg" "$out" "Applied:"

# Verify settings.json modifications
removed_absent=$(jq -e '.enabledPlugins | has("removed@market1") | not' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
newcomer_present=$(jq -e '.enabledPlugins["newcomer@market1"] == false' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
alpha_preserved=$(jq -e '.enabledPlugins["alpha@market1"] == true' "$case_dir/settings.json" >/dev/null && echo yes || echo no)

assert_eq "case-3: orphan removed" "yes" "$removed_absent"
assert_eq "case-3: new added as false" "yes" "$newcomer_present"
assert_eq "case-3: existing entry preserved" "yes" "$alpha_preserved"

# --- Case 4: true-orphan surfaced but NOT auto-removed ----------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "broken-but-enabled", "marketplace": "market1", "enabled": true}],
  "new_upstream": [],
  "renames": []
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "broken-but-enabled@market1": true
  }
}
EOF

out=$(run_fix_apply "$case_dir") || true

assert_contains "case-4: MANUAL REVIEW header" "$out" "MANUAL REVIEW"
assert_contains "case-4: lists the broken plugin" "$out" "broken-but-enabled@market1"

# Settings.json must NOT have removed the true-orphan
preserved=$(jq -e '.enabledPlugins["broken-but-enabled@market1"] == true' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-4: true-orphan preserved (not auto-removed)" "yes" "$preserved"

# --- Case 5: rename surfaced as advisory -------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "old-name", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "old-name-renamed", "marketplace": "market1"}],
  "renames": [{"from": "old-name", "to": "old-name-renamed", "marketplace": "market1"}]
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "old-name@market1": false
  }
}
EOF

out=$(run_fix_dry "$case_dir") || true

assert_contains "case-5: RENAME advisory" "$out" "RENAME?"
assert_contains "case-5: pair shown" "$out" "old-name -> old-name-renamed"

# --- Case 6: dry-run with empty findings is a safe no-op --------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
echo '[]' >"$case_dir/findings.json"
echo 'not valid json' >"$case_dir/settings.json"

# fix-plugin-drift.sh does not validate settings.json on the dry-run path (no edit).
# The apply path validates. Dry-run reads findings.json only.
exit_code=0
out=$(run_fix_dry "$case_dir" 2>&1) || exit_code=$?

assert_exit "case-6: dry-run with empty findings exits 0" 0 "$exit_code"

# --- Case 7: jq-metacharacter plugin name is treated as data, not filter code ------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
evil='a"]) | halt_error | path(["b'
jq -n --arg evil "$evil" '[{
  key: "market1",
  status: "ok",
  skip_reason: "",
  orphans: [{name: $evil, marketplace: "market1", enabled: false}],
  new_upstream: [],
  renames: []
}]' >"$case_dir/findings.json"
jq -n --arg evil "$evil" '{enabledPlugins: {($evil + "@market1"): false, "alpha@market1": true}}' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?

assert_exit "case-7: apply with hostile name exits 0" 0 "$exit_code"
evil_absent=$(jq -e --arg evil "$evil" '.enabledPlugins | has($evil + "@market1") | not' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
alpha_preserved=$(jq -e '.enabledPlugins["alpha@market1"] == true' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-7: hostile-name entry removed literally" "yes" "$evil_absent"
assert_eq "case-7: other entries untouched (no filter injection)" "yes" "$alpha_preserved"

# --- Final ------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
