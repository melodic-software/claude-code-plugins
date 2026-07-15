#!/usr/bin/env bash
# Black-box contract tests for check-plugin-drift.sh (self-contained — ships with the plugin).
# Uses SETTINGS_AUDIT_FIXTURE_DIR to short-circuit network calls.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-plugin-drift.sh"
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
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "unexpected substring: $3" ;;
    *) pass "$1" ;;
  esac
}
assert_file_exists() {
  if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "file absent: $2"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# --- Fixture builders ----------------------------------------------------------

make_fixture_dir() {
  local case_dir="$TEST_TMPDIR/case-$CASE_NUM"
  mkdir -p "$case_dir/fixtures"
  echo "$case_dir"
}

write_settings() {
  local path="$1" json="$2"
  echo "$json" >"$path"
}

write_fixture() {
  local fixture_dir="$1" market_key="$2" upstream_json="$3"
  echo "$upstream_json" >"$fixture_dir/$market_key.json"
}

run_check() {
  local case_dir="$1"
  NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
    SETTINGS_AUDIT_FIXTURE_DIR="$case_dir/fixtures" \
    bash "$SCRIPT" 2>&1
}

# --- Case 1: no drift -----------------------------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {
    "alpha@market1": true,
    "beta@market1": false
  },
  "extraKnownMarketplaces": {
    "market1": {"source": {"source": "github", "repo": "owner/market1"}}
  }
}'
write_fixture "$case_dir/fixtures" "market1" '{
  "name": "market1",
  "plugins": [{"name": "alpha"}, {"name": "beta"}]
}'

exit_code=0
out=$(run_check "$case_dir") || exit_code=$?

assert_exit "case-1: no drift exits 0" 0 "$exit_code"
assert_contains "case-1: shows OK" "$out" "OK    no drift"
assert_not_contains "case-1: no orphan reported" "$out" "ORPHAN"
assert_not_contains "case-1: no new reported" "$out" "NEW     "

# --- Case 2: orphan (false) detected ---------------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed-plugin@market1": false
  },
  "extraKnownMarketplaces": {
    "market1": {"source": {"source": "github", "repo": "owner/market1"}}
  }
}'
write_fixture "$case_dir/fixtures" "market1" '{
  "name": "market1",
  "plugins": [{"name": "alpha"}]
}'

exit_code=0
out=$(run_check "$case_dir") || exit_code=$?

assert_exit "case-2: drift exits 1" 1 "$exit_code"
assert_contains "case-2: orphan listed" "$out" "removed-plugin@market1"
assert_contains "case-2: marked auto-removable" "$out" "auto-removable"

# --- Case 3: orphan (true) flagged for manual review -----------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {
    "user-enabled-but-removed@market1": true
  },
  "extraKnownMarketplaces": {
    "market1": {"source": {"source": "github", "repo": "owner/market1"}}
  }
}'
write_fixture "$case_dir/fixtures" "market1" '{
  "name": "market1",
  "plugins": []
}'

out=$(run_check "$case_dir") || true

assert_contains "case-3: true-orphan listed" "$out" "user-enabled-but-removed@market1"
assert_contains "case-3: marked manual review" "$out" "manual review required"

# --- Case 4: new upstream plugin detected ----------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {
    "alpha@market1": true
  },
  "extraKnownMarketplaces": {
    "market1": {"source": {"source": "github", "repo": "owner/market1"}}
  }
}'
write_fixture "$case_dir/fixtures" "market1" '{
  "name": "market1",
  "plugins": [{"name": "alpha"}, {"name": "newcomer"}, {"name": "another-new"}]
}'

exit_code=0
out=$(run_check "$case_dir") || exit_code=$?

assert_exit "case-4: drift exits 1" 1 "$exit_code"
assert_contains "case-4: NEW header present" "$out" "NEW"
assert_contains "case-4: newcomer listed" "$out" "newcomer@market1"
assert_contains "case-4: another-new listed" "$out" "another-new@market1"

# --- Case 5: marketplace fetch failure → SKIP ------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {
    "alpha@unreachable-market": false
  },
  "extraKnownMarketplaces": {
    "unreachable-market": {"source": {"source": "github", "repo": "owner/unreachable"}}
  }
}'
# Intentionally do NOT write a fixture for unreachable-market

exit_code=0
out=$(run_check "$case_dir") || exit_code=$?

assert_contains "case-5: SKIP shown" "$out" "SKIP"
assert_contains "case-5: fetch reason" "$out" "upstream fetch failed"
assert_exit "case-5: skip alone does not fail (exit 0)" 0 "$exit_code"

# --- Case 6: rename heuristic flag -----------------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {
    "frontend-design@market1": false
  },
  "extraKnownMarketplaces": {
    "market1": {"source": {"source": "github", "repo": "owner/market1"}}
  }
}'
write_fixture "$case_dir/fixtures" "market1" '{
  "name": "market1",
  "plugins": [{"name": "frontend-designer"}]
}'

out=$(run_check "$case_dir") || true

assert_contains "case-6: RENAME heading present" "$out" "RENAME?"
assert_contains "case-6: rename pair shown" "$out" "frontend-design -> frontend-designer"

# --- Case 7: empty extraKnownMarketplaces ----------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {}
}'

exit_code=0
out=$(run_check "$case_dir") || exit_code=$?

assert_contains "case-7: no marketplaces note" "$out" "no marketplaces declared"
assert_exit "case-7: exit 0" 0 "$exit_code"

# --- Case 8: SETTINGS_AUDIT_OUTPUT_JSON writes structured findings ----------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)

write_settings "$case_dir/settings.json" '{
  "enabledPlugins": {
    "removed@market1": false
  },
  "extraKnownMarketplaces": {
    "market1": {"source": {"source": "github", "repo": "owner/market1"}}
  }
}'
write_fixture "$case_dir/fixtures" "market1" '{
  "name": "market1",
  "plugins": [{"name": "newcomer"}]
}'

OUTPUT_JSON_PATH="$case_dir/findings.json"
NO_COLOR=1 \
  CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
  SETTINGS_AUDIT_FIXTURE_DIR="$case_dir/fixtures" \
  SETTINGS_AUDIT_OUTPUT_JSON="$OUTPUT_JSON_PATH" \
  bash "$SCRIPT" >/dev/null 2>&1 || true

assert_file_exists "case-8: JSON written" "$OUTPUT_JSON_PATH"
orphan_name=$(jq -r '.[0].orphans[0].name // ""' "$OUTPUT_JSON_PATH")
new_name=$(jq -r '.[0].new_upstream[0].name // ""' "$OUTPUT_JSON_PATH")
assert_eq "case-8: JSON orphan name" "removed" "$orphan_name"
assert_eq "case-8: JSON new name" "newcomer" "$new_name"

# --- Final ------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
