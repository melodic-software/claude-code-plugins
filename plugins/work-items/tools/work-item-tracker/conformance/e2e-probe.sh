#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by sourced tests/lib.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$SCRIPT_DIR/../work-item-tracker.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "usage: e2e-probe.sh [--evidence <file>]  (drives the full lifecycle — map, items, edge, frontier, claim/lease, renew, close, graduation — against a live GitHub sandbox; target required: WIT_CONFORMANCE_GITHUB_REPO=owner/name)"
  exit 0
fi

usage_error() {
  echo "usage: e2e-probe.sh [--evidence <file>]" >&2
  exit 2
}

EVIDENCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --evidence)
    [[ $# -ge 2 ]] || usage_error
    EVIDENCE="$2"
    shift 2
    ;;
  *)
    usage_error
    ;;
  esac
done

REPO="${WIT_CONFORMANCE_GITHUB_REPO:?set WIT_CONFORMANCE_GITHUB_REPO to a throwaway sandbox repo (owner/name); never a coordination repo}"

BINDING_TMP="$(mktemp)"
trap 'rm -f "$BINDING_TMP"' EXIT
printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}' >"$BINDING_TMP"
export WORK_ITEM_TRACKER_BINDING="$BINDING_TMP"

record() {
  if [[ -n "$EVIDENCE" ]]; then
    # shellcheck disable=SC2016  # backticks are a literal markdown code fence
    printf '## %s\n\n```json\n%s\n```\n' "$1" "$2" >>"$EVIDENCE"
  fi
}

wit() {
  bash "$TRACKER" "$@"
}

ids() {
  jq -c '[.items[].id]' <<<"$1"
}

for n in $(gh issue list -R "$REPO" --state open --limit 200 --json number --jq '.[].number' | tr -d '\r'); do
  gh issue close "$n" -R "$REPO" --comment "e2e-probe clean-at-start" >/dev/null 2>&1 || true
done
for label in spec-container "wayfind: research" "wayfind: task"; do
  gh label create "$label" -R "$REPO" --force >/dev/null 2>&1 || true
done

TS="$(date -u +%Y%m%dT%H%M%SZ)"

MAP="$(wit create-item --title "e2e map $TS" --body "e2e lifecycle probe map" --labels spec-container --repo "$REPO")"
MAP_ID="$(jq -r '.id' <<<"$MAP")"
record "create map" "$MAP"
assert_contains "map id well-formed" "$MAP_ID" "github:"

ITEM1="$(wit create-item --title "e2e work item $TS" --parent "$MAP_ID" --repo "$REPO")"
ITEM1_ID="$(jq -r '.id' <<<"$ITEM1")"
record "create item1" "$ITEM1"
ITEM2="$(wit create-item --title "e2e blocked work item $TS" --parent "$MAP_ID" --blocked-by "$ITEM1_ID" --repo "$REPO")"
ITEM2_ID="$(jq -r '.id' <<<"$ITEM2")"
record "create item2 (blocked by item1)" "$ITEM2"
assert_eq "item2 parent is map" "$MAP_ID" "$(jq -r '.parent_id' <<<"$ITEM2")"
assert_eq "item2 blocked" "1" "$(jq -r '.blocked_by_count' <<<"$ITEM2")"
WAYFIND="$(wit create-item --title "e2e wayfind research item $TS" --labels "wayfind: research" --parent "$MAP_ID" --repo "$REPO")"
WAYFIND_ID="$(jq -r '.id' <<<"$WAYFIND")"
record "create wayfind item (research)" "$WAYFIND"

FRONTIER="$(wit list-frontier --repo "$REPO")"
record "frontier before claim" "$FRONTIER"
IDS="$(ids "$FRONTIER")"
assert_contains "frontier holds item1" "$IDS" "$ITEM1_ID"
assert_not_contains "frontier hides blocked item2" "$IDS" "$ITEM2_ID"
assert_not_contains "frontier excludes the unblocked container map" "$IDS" "$MAP_ID"
assert_not_contains "frontier excludes the wayfind item" "$IDS" "$WAYFIND_ID"

SUBS="$(wit list-sub-items "$MAP_ID")"
record "map sub-items" "$SUBS"
SUB_IDS="$(ids "$SUBS")"
assert_contains "sub-items hold item1" "$SUB_IDS" "$ITEM1_ID"
assert_contains "sub-items hold blocked item2" "$SUB_IDS" "$ITEM2_ID"
assert_eq "sub-items are re-parented to the map" "$MAP_ID" "$(jq -r '.items[0].parent_id' <<<"$SUBS")"

PFRONTIER="$(wit list-frontier --parent "$MAP_ID")"
record "scoped frontier before claim" "$PFRONTIER"
PIDS="$(ids "$PFRONTIER")"
assert_contains "scoped frontier holds item1" "$PIDS" "$ITEM1_ID"
assert_not_contains "scoped frontier hides blocked item2" "$PIDS" "$ITEM2_ID"
assert_not_contains "scoped frontier excludes the map itself" "$PIDS" "$MAP_ID"
assert_not_contains "scoped frontier excludes the wayfind item" "$PIDS" "$WAYFIND_ID"

CLAIM="$(wit claim "$ITEM1_ID" --session-id "e2e-$TS")"
record "claim item1" "$CLAIM"
LEASE_CID="$(jq -r '.lease_comment_id' <<<"$CLAIM")"
if [[ "$LEASE_CID" =~ ^[0-9]+$ ]]; then
  pass "lease_comment_id shape"
else
  fail "lease_comment_id shape" "numeric" "$LEASE_CID"
fi

RENEW="$(wit renew-lease "$ITEM1_ID" --lease-comment-id "$LEASE_CID")"
record "renew lease" "$RENEW"
assert_eq "renew keeps holder" "$(jq -r '.holder' <<<"$CLAIM")" "$(jq -r '.holder' <<<"$RENEW")"

gh issue close "${ITEM1_ID##*#}" -R "$REPO" --comment "e2e: resolved" >/dev/null

FRONTIER2="$(wit list-frontier --repo "$REPO")"
record "frontier after item1 closed" "$FRONTIER2"
IDS2="$(ids "$FRONTIER2")"
assert_contains "item2 graduated into frontier" "$IDS2" "$ITEM2_ID"
assert_not_contains "closed item1 out of frontier" "$IDS2" "$ITEM1_ID"

gh issue close "${ITEM2_ID##*#}" -R "$REPO" --comment "e2e: done" >/dev/null
gh issue close "${WAYFIND_ID##*#}" -R "$REPO" --comment "e2e: done" >/dev/null
gh issue close "${MAP_ID##*#}" -R "$REPO" --comment "e2e: map closed" >/dev/null

printf '\ne2e-probe: %d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
