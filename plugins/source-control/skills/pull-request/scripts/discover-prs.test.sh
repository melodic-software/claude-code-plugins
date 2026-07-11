#!/usr/bin/env bash
# Regression tests for discover-prs.sh.
# Black-box: feed fixture PR JSON via --prs-json (no network). Asserts the
# §5.0.2 filter contract — drop drafts, oldest-first. Dependabot (and every
# other author) is in scope; no author filter (babysit covers all PR authors).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER="$SCRIPT_DIR/discover-prs.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-helpers.sh"

# run_discover <fixture-json> — emits stdout then "EXIT:<code>".
run_discover() {
  local fixture="$1"
  local out
  out=$(bash "$DISCOVER" --prs-json "$fixture" 2>/dev/null)
  local code=$?
  printf '%s\nEXIT:%s' "$out" "$code"
}

# numbers_of <fixture-json> — output PR numbers as a comma-joined string.
numbers_of() {
  local fixture="$1"
  bash "$DISCOVER" --prs-json "$fixture" 2>/dev/null | jq -r '[.[].number] | join(",")'
}

mkjson() { # mkjson <name> <jq-array-expr>
  local f="$TEST_TMPDIR/$1.json"
  jq -n "$2" >"$f"
  printf '%s' "$f"
}

# --- Case: --help exits 0, non-empty, describes the skill ---
help_out=$(bash "$DISCOVER" --help 2>&1)
assert_exit "--help exit 0" 0 "$?"
assert_contains "--help non-empty / describes discovery" "$help_out" "PR discovery"

# --- Case: unknown flag ---
bash "$DISCOVER" --bogus >/dev/null 2>&1
assert_exit "unknown flag exit 1" 1 "$?"

# --- Case: unexpected positional argument ---
bash "$DISCOVER" 123 >/dev/null 2>&1
assert_exit "positional arg exit 1" 1 "$?"

# --- Case: missing fixture file ---
bash "$DISCOVER" --prs-json "$TEST_TMPDIR/nope.json" >/dev/null 2>&1
assert_exit "missing fixture exit 1" 1 "$?"

# --- Case: --prs-json with no argument must error, not hang ---
# Regression: `shift 2` with $#==1 under `set -uo pipefail` (no -e) left $#
# unchanged and looped forever (exit 124). The guard must exit 1 immediately.
# timeout bounds the regression so a reintroduced hang fails the suite rather
# than blocking it; degrade to skip on platforms lacking timeout (BSD macOS).
if command -v timeout >/dev/null 2>&1; then
  timeout 5 bash "$DISCOVER" --prs-json >/dev/null 2>&1
  assert_exit "--prs-json without arg errors (no infinite loop)" 1 "$?"
else
  skip_case "timeout unavailable — cannot bound --prs-json infinite-loop regression"
fi

# --- Case: combined filter — drop draft only, oldest-first; Dependabot KEPT ---
# Out-of-order numbers, one draft, one Dependabot PR mixed in. The draft (#18)
# is dropped; the Dependabot PR (#5) is KEPT. Surviving set {5, 7, 12, 30} in
# ascending order proves drop-draft + keep-all-authors + oldest-first together.
F=$(mkjson combined '[
  {number:30, title:"c", headRefName:"feat/c", isDraft:false, author:{login:"alice"}},
  {number:7,  title:"a", headRefName:"feat/a", isDraft:false, author:{login:"bob"}},
  {number:18, title:"draft", headRefName:"feat/d", isDraft:true,  author:{login:"carol"}},
  {number:5,  title:"dep", headRefName:"dependabot/nuget/x", isDraft:false, author:{login:"app/dependabot"}},
  {number:12, title:"b", headRefName:"feat/b", isDraft:false, author:{login:"alice"}}
]')
assert_eq "combined -> drop draft, keep dependabot, oldest-first" "5,7,12,30" "$(numbers_of "$F")"
r=$(run_discover "$F")
assert_contains "combined exit 0" "$r" "EXIT:0"

# --- Case: Dependabot PR is KEPT; only the draft is dropped (codex r3327055703) -
# Babysit covers ALL PR authors incl Dependabot. The non-draft
# Dependabot PR (#3) survives; the draft (#2) is dropped.
F=$(mkjson depkept '[
  {number:2, title:"draft", headRefName:"feat/d", isDraft:true, author:{login:"alice"}},
  {number:3, title:"dep", headRefName:"dependabot/npm/y", isDraft:false, author:{login:"app/dependabot"}}
]')
assert_eq "dependabot kept, draft dropped" "3" "$(numbers_of "$F")"
r=$(run_discover "$F")
assert_contains "dependabot-kept exit 0" "$r" "EXIT:0"

# --- Case: all-draft input -> empty list ([] from non-empty input) ---
F=$(mkjson alldraft '[
  {number:2, title:"draft", headRefName:"feat/d", isDraft:true, author:{login:"alice"}}
]')
assert_eq "all-draft -> empty number list" "" "$(numbers_of "$F")"
r=$(run_discover "$F")
assert_contains "all-draft -> []" "$r" "[]"
assert_contains "all-draft exit 0" "$r" "EXIT:0"

# --- Case: empty discovery (zero open PRs) ---
F=$(mkjson empty '[]')
r=$(run_discover "$F")
assert_contains "empty -> []" "$r" "[]"
assert_contains "empty exit 0" "$r" "EXIT:0"

# --- Case: null author kept (no author filter at all) ---
# Only drafts are dropped, so a PR with a null author survives regardless.
F=$(mkjson nullauthor '[
  {number:9, title:"ghost", headRefName:"feat/g", isDraft:false, author:null}
]')
assert_eq "null-author kept" "9" "$(numbers_of "$F")"

# --- Case: malformed input (object, not array) ---
F=$(mkjson malformed '{number:1}')
bash "$DISCOVER" --prs-json "$F" >/dev/null 2>&1
assert_exit "malformed input exit 1" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
