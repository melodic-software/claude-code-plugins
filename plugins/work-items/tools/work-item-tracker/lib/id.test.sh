#!/usr/bin/env bash
# Tests for lib/id.sh (CONTRACT.md "ID grammar").
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=id.sh
source "$SCRIPT_DIR/id.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

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
  assert_fails "rejects malformed id: ${bad:-<empty>}" "parse failure" "parsed" \
    wit_parse_id "$bad"
done

# --- change-link helpers ---

wit_parse_id "github:acme/webapp#42"
assert_eq "hash ref short in the item's repo" "#42" "$(wit_hash_ref acme/webapp)"
assert_eq "hash ref qualified from another repo" "acme/webapp#42" "$(wit_hash_ref acme/other)"
assert_eq "hash ref qualified without a repo" "acme/webapp#42" "$(wit_hash_ref "")"

out="$(wit_emit_change_link "jira:s/SW2#1" "" "Refs: SW2-1" "SW2-1")"
assert_eq "empty closes is null" "null" "$(jq -r '.closes' <<<"$out")"
assert_eq "refs carried" "Refs: SW2-1" "$(jq -r '.refs' <<<"$out")"
assert_eq "schema_version carried" "1.0" "$(jq -r '.schema_version' <<<"$out")"

wit_usage_error() { exit 2; }
cl_rc() { (wit_change_link_args "$@" >/dev/null 2>&1 && echo 0) || echo 2; }
assert_eq "id alone parses" "0" "$(cl_rc "github:o/r#1")"
assert_eq "branch ref with repo parses" "0" "$(cl_rc --branch-ref 1 --repo o/r)"
assert_eq "no input is a usage error" "2" "$(cl_rc --repo o/r)"
assert_eq "id and branch ref together is a usage error" "2" "$(cl_rc "github:o/r#1" --branch-ref 1)"
assert_eq "malformed repo is a usage error" "2" "$(cl_rc "github:o/r#1" --repo 'o/r;x')"
assert_eq "unknown flag is a usage error" "2" "$(cl_rc --nope)"

[[ $FAILED -eq 0 ]] || exit 1
