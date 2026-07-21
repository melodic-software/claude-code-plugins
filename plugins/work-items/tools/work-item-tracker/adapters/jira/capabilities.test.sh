#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/capabilities.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" extra-arg

# Emits the manifest as compact JSON, offline (no binding, no network). The manifest
# must declare the consume-only posture: reads on, every write verb + list-sub-items
# off (issue #379 hard constraint — no code path mutates a Jira ticket by default).
out="$(bash "$S" 2>/dev/null)"
assert_eq "capabilities exit 0" "0" "$?"
assert_eq "provider is jira" "jira" "$(jq -r '.provider' <<<"$out")"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$out")"
for v in get-item list-items capabilities; do
  assert_eq "read verb $v supported" "true" "$(jq -r --arg v "$v" '.verbs[$v]' <<<"$out")"
done
for v in create-item claim renew-lease reclaim link-blocks add-sub-item list-sub-items; do
  assert_eq "write/unsupported verb $v is false" "false" "$(jq -r --arg v "$v" '.verbs[$v]' <<<"$out")"
done
assert_eq "leases feature off" "false" "$(jq -r '.features.leases' <<<"$out")"
assert_eq "sub_items feature off" "false" "$(jq -r '.features.sub_items' <<<"$out")"
assert_eq "labels feature on" "true" "$(jq -r '.features.labels' <<<"$out")"

[[ $FAILED -eq 0 ]] || exit 1
