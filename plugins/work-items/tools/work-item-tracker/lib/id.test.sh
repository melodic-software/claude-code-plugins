#!/usr/bin/env bash
# Tests for lib/id.sh (CONTRACT.md "ID grammar").
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=id.sh
source "$SCRIPT_DIR/id.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

# --- valid IDs ---

wit_parse_id "github:acme/webapp#1335"
assert_eq "provider parsed" "github" "$WIT_ID_PROVIDER"
assert_eq "owner parsed" "acme" "$WIT_ID_OWNER"
assert_eq "repo parsed" "webapp" "$WIT_ID_REPO"
assert_eq "number parsed" "1335" "$WIT_ID_NUMBER"

wit_parse_id "local-markdown:o/r.dot#7"
assert_eq "provider with dash" "local-markdown" "$WIT_ID_PROVIDER"
assert_eq "repo with dot" "r.dot" "$WIT_ID_REPO"

assert_eq "make_id round-trip" "github:o/r#12" "$(wit_make_id github o r 12)"

# --- invalid IDs ---

for bad in "#123" "123" "github:#123" "github:owner#123" "github:owner/repo" \
  "github:owner/repo#" "github:owner/repo#12a" "GitHub:o/r#1" "" "github:o/r#1 trailing"; do
  if wit_parse_id "$bad" 2>/dev/null; then
    fail "rejects malformed id: ${bad:-<empty>}" "parse failure" "parsed"
  else
    pass "rejects malformed id: ${bad:-<empty>}"
  fi
done

[[ $FAILED -eq 0 ]] || exit 1
