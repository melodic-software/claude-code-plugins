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

# Directory-source cases need a project root that owns a `.claude/` directory,
# because a relative `source.path` resolves against dirname(dirname(settings)).
make_project_dir() {
  local case_dir="$1"
  mkdir -p "$case_dir/project/.claude"
  echo "$case_dir/project"
}

write_directory_catalog() {
  local catalog_dir="$1" catalog_json="$2"
  mkdir -p "$catalog_dir/.claude-plugin"
  echo "$catalog_json" >"$catalog_dir/.claude-plugin/marketplace.json"
}

# No SETTINGS_AUDIT_FIXTURE_DIR: a directory source reads its catalog from disk.
run_check_dir() {
  local project_dir="$1"
  NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$project_dir/.claude/settings.json" \
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

# --- Case 9: directory source (./) with NEW and ORPHAN ---------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@local-market": true,
    "gone@local-market": false
  },
  "extraKnownMarketplaces": {
    "local-market": {"source": {"source": "directory", "path": "./"}}
  }
}'
write_directory_catalog "$project_dir" '{
  "name": "local-market",
  "plugins": [{"name": "alpha"}, {"name": "fresh"}]
}'

exit_code=0
out=$(run_check_dir "$project_dir") || exit_code=$?

assert_exit "case-9: directory drift exits 1" 1 "$exit_code"
assert_contains "case-9: header names directory source" "$out" "directory:$project_dir"
assert_contains "case-9: NEW header present" "$out" "NEW"
assert_contains "case-9: fresh listed as new" "$out" "fresh@local-market"
assert_contains "case-9: ORPHAN header present" "$out" "ORPHAN"
assert_contains "case-9: gone listed as orphan" "$out" "gone@local-market"
assert_not_contains "case-9: no SKIP" "$out" "SKIP"

# --- Case 10: directory source with no drift -------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@local-market": true,
    "beta@local-market": false
  },
  "extraKnownMarketplaces": {
    "local-market": {"source": {"source": "directory", "path": "./"}}
  }
}'
write_directory_catalog "$project_dir" '{
  "name": "local-market",
  "plugins": [{"name": "alpha"}, {"name": "beta"}]
}'

exit_code=0
out=$(run_check_dir "$project_dir") || exit_code=$?

assert_exit "case-10: directory no drift exits 0" 0 "$exit_code"
assert_contains "case-10: shows OK" "$out" "OK    no drift"
assert_contains "case-10: header names directory source" "$out" "directory:"

# --- Case 11: directory catalog absent → SKIP naming the path --------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@local-market": true
  },
  "extraKnownMarketplaces": {
    "local-market": {"source": {"source": "directory", "path": "./missing"}}
  }
}'
# Intentionally do NOT write a catalog under project/missing

exit_code=0
out=$(run_check_dir "$project_dir") || exit_code=$?

assert_contains "case-11: SKIP shown" "$out" "SKIP"
assert_contains "case-11: reason names resolved path" "$out" \
  "directory catalog not found at $project_dir/missing/.claude-plugin/marketplace.json"
assert_exit "case-11: skip alone does not fail (exit 0)" 0 "$exit_code"

# --- Case 12: directory catalog invalid JSON → SKIP -------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@local-market": true
  },
  "extraKnownMarketplaces": {
    "local-market": {"source": {"source": "directory", "path": "./"}}
  }
}'
write_directory_catalog "$project_dir" '{ not json'

exit_code=0
out=$(run_check_dir "$project_dir") || exit_code=$?

assert_contains "case-12: SKIP shown" "$out" "SKIP"
assert_contains "case-12: invalid JSON reason" "$out" "directory catalog is not valid JSON"
assert_exit "case-12: skip alone does not fail (exit 0)" 0 "$exit_code"

# --- Case 13: JSON output carries source per marketplace ---------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@local-market": true,
    "alpha@remote-market": true
  },
  "extraKnownMarketplaces": {
    "local-market": {"source": {"source": "directory", "path": "./"}},
    "remote-market": {"source": {"source": "github", "repo": "owner/remote"}}
  }
}'
write_directory_catalog "$project_dir" '{
  "name": "local-market",
  "plugins": [{"name": "alpha"}, {"name": "fresh"}]
}'
write_fixture "$case_dir/fixtures" "remote-market" '{
  "name": "remote-market",
  "plugins": [{"name": "alpha"}]
}'

OUTPUT_JSON_PATH="$case_dir/findings.json"
NO_COLOR=1 \
  CLAUDE_SETTINGS_FILE="$project_dir/.claude/settings.json" \
  SETTINGS_AUDIT_FIXTURE_DIR="$case_dir/fixtures" \
  SETTINGS_AUDIT_OUTPUT_JSON="$OUTPUT_JSON_PATH" \
  bash "$SCRIPT" >/dev/null 2>&1 || true

assert_file_exists "case-13: JSON written" "$OUTPUT_JSON_PATH"
local_source=$(jq -r '.[] | select(.key == "local-market") | .source // ""' "$OUTPUT_JSON_PATH")
remote_source=$(jq -r '.[] | select(.key == "remote-market") | .source // ""' "$OUTPUT_JSON_PATH")
local_new=$(jq -r '.[] | select(.key == "local-market") | .new_upstream[0].name // ""' "$OUTPUT_JSON_PATH")
remote_status=$(jq -r '.[] | select(.key == "remote-market") | .status // ""' "$OUTPUT_JSON_PATH")
assert_eq "case-13: directory block source" "directory" "$local_source"
assert_eq "case-13: repo block source" "repo" "$remote_source"
assert_eq "case-13: directory block new name" "fresh" "$local_new"
assert_eq "case-13: repo block still takes fixture route" "ok" "$remote_status"

# --- Case 14: directory wins over repo; fixture seam not consulted ---------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@dual-market": true
  },
  "extraKnownMarketplaces": {
    "dual-market": {"source": {"source": "directory", "path": "./", "repo": "owner/dual"}}
  }
}'
write_directory_catalog "$project_dir" '{
  "name": "dual-market",
  "plugins": [{"name": "alpha"}, {"name": "on-disk-only"}]
}'
# A decoy fixture for the same key: a directory source must never read it.
write_fixture "$case_dir/fixtures" "dual-market" '{
  "name": "dual-market",
  "plugins": [{"name": "alpha"}, {"name": "decoy-from-fixture"}]
}'

exit_code=0
out=$(NO_COLOR=1 \
  CLAUDE_SETTINGS_FILE="$project_dir/.claude/settings.json" \
  SETTINGS_AUDIT_FIXTURE_DIR="$case_dir/fixtures" \
  bash "$SCRIPT" 2>&1) || exit_code=$?

assert_exit "case-14: drift from on-disk catalog exits 1" 1 "$exit_code"
assert_contains "case-14: header names directory source" "$out" "directory:$project_dir"
assert_not_contains "case-14: header does not name repo" "$out" "owner/dual"
assert_contains "case-14: on-disk plugin listed" "$out" "on-disk-only@dual-market"
assert_not_contains "case-14: fixture decoy not consulted" "$out" "decoy-from-fixture"

# --- Case 15: relative subpath with backslashes and trailing slash ---------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

# The path spells each backslash as the JSON escape \u005c, so the fixture
# decodes to a Windows path without the source carrying a regex-looking escape.
write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@sub-market": true
  },
  "extraKnownMarketplaces": {
    "sub-market": {"source": {"source": "directory", "path": ".\u005ccatalogs\u005csub/"}}
  }
}'
write_directory_catalog "$project_dir/catalogs/sub" '{
  "name": "sub-market",
  "plugins": [{"name": "alpha"}]
}'

exit_code=0
out=$(run_check_dir "$project_dir") || exit_code=$?

assert_exit "case-15: normalized subpath resolves (exit 0)" 0 "$exit_code"
assert_contains "case-15: header shows normalized path" "$out" "directory:$project_dir/catalogs/sub)"
assert_contains "case-15: shows OK" "$out" "OK    no drift"

# --- Case 16: absolute directory path used as is --------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")
external_dir="$case_dir/elsewhere"

write_settings "$project_dir/.claude/settings.json" "{
  \"enabledPlugins\": {
    \"alpha@abs-market\": true
  },
  \"extraKnownMarketplaces\": {
    \"abs-market\": {\"source\": {\"source\": \"directory\", \"path\": \"$external_dir/\"}}
  }
}"
write_directory_catalog "$external_dir" '{
  "name": "abs-market",
  "plugins": [{"name": "alpha"}]
}'

exit_code=0
out=$(run_check_dir "$project_dir") || exit_code=$?

assert_exit "case-16: absolute path resolves (exit 0)" 0 "$exit_code"
assert_contains "case-16: header shows absolute path" "$out" "directory:$external_dir)"
assert_contains "case-16: shows OK" "$out" "OK    no drift"

# --- Case 17: directory type without path and without repo → SKIP ---------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_fixture_dir)
project_dir=$(make_project_dir "$case_dir")

write_settings "$project_dir/.claude/settings.json" '{
  "enabledPlugins": {
    "alpha@bare-market": true
  },
  "extraKnownMarketplaces": {
    "bare-market": {"source": {"source": "directory"}}
  }
}'

exit_code=0
out=$(run_check_dir "$project_dir") || exit_code=$?

assert_contains "case-17: SKIP shown" "$out" "SKIP"
assert_contains "case-17: falls back to no-repo reason" "$out" "no source.repo declared"
assert_exit "case-17: exit 0" 0 "$exit_code"

# --- Final ------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
