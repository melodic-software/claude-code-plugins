#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by sourced tests/lib.sh
# End-to-end lifecycle probe against a live GitHub sandbox: map → typed sub-items →
# dependency edge → frontier → claim/lease → renew → resolve+close → graduation →
# map close. Exercises every seam verb through the core CLI plus the
# closed-blocker-graduation semantics the frontier depends on. On-demand only.
# Usage: e2e-probe.sh [--evidence <file>]   (target required: WIT_CONFORMANCE_GITHUB_REPO=owner/name)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$SCRIPT_DIR/../work-item-tracker.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "usage: e2e-probe.sh [--evidence <file>]  (drives the full lifecycle — map, typed items, edge, frontier, claim/lease, renew, close, graduation — against a live GitHub sandbox; target required: WIT_CONFORMANCE_GITHUB_REPO=owner/name)"
  exit 0
fi

EVIDENCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence)
      [[ $# -ge 2 ]] || {
        echo "usage: e2e-probe.sh [--evidence <file>]" >&2
        exit 2
      }
      EVIDENCE="$2"
      shift 2
      ;;
    *)
      echo "usage: e2e-probe.sh [--evidence <file>]" >&2
      exit 2
      ;;
  esac
done

# Required target — guarded after arg-parsing so usage errors still exit 2.
REPO="${WIT_CONFORMANCE_GITHUB_REPO:?set WIT_CONFORMANCE_GITHUB_REPO to a throwaway sandbox repo (owner/name); NEVER a coordination repo}"

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

# Clean slate.
for n in $(gh issue list -R "$REPO" --state open --limit 200 --json number --jq '.[].number' | tr -d '\r'); do
  gh issue close "$n" -R "$REPO" --comment "e2e-probe clean-at-start" >/dev/null 2>&1 || true
done
gh label create work-map -R "$REPO" --force >/dev/null 2>&1 || true
gh label create "wayfind:research" -R "$REPO" --force >/dev/null 2>&1 || true
gh label create "wayfind:task" -R "$REPO" --force >/dev/null 2>&1 || true

TS="$(date -u +%Y%m%dT%H%M%SZ)"

# 1. Map issue (container: bare work-map marker).
MAP="$(wit create-item --title "e2e map $TS" --body "e2e lifecycle probe map" --labels work-map --repo "$REPO")"
MAP_ID="$(jq -r '.id' <<<"$MAP")"
record "create map" "$MAP"
assert_contains "map id well-formed" "$MAP_ID" "github:"

# 2. Two typed decision items under the map; item2 blocked by item1.
ITEM1="$(wit create-item --title "e2e research item $TS" --labels "wayfind:research" --parent "$MAP_ID" --repo "$REPO")"
ITEM1_ID="$(jq -r '.id' <<<"$ITEM1")"
record "create item1 (research)" "$ITEM1"
ITEM2="$(wit create-item --title "e2e task item $TS" --labels "wayfind:task" --parent "$MAP_ID" --blocked-by "$ITEM1_ID" --repo "$REPO")"
ITEM2_ID="$(jq -r '.id' <<<"$ITEM2")"
record "create item2 (task, blocked by item1)" "$ITEM2"
assert_eq "item2 parent is map" "$MAP_ID" "$(jq -r '.parent_id' <<<"$ITEM2")"
assert_eq "item2 blocked" "1" "$(jq -r '.blocked_by_count' <<<"$ITEM2")"

# 3. Frontier: item1 claimable, item2 blocked.
FRONTIER="$(wit list-frontier --repo "$REPO")"
record "frontier before claim" "$FRONTIER"
IDS="$(jq -c '[.items[].id]' <<<"$FRONTIER")"
assert_contains "frontier holds item1" "$IDS" "$ITEM1_ID"
assert_not_contains "frontier hides blocked item2" "$IDS" "$ITEM2_ID"

# 4. Claim item1 (assignee + lease comment).
CLAIM="$(wit claim "$ITEM1_ID" --session-id "e2e-$TS")"
record "claim item1" "$CLAIM"
LEASE_CID="$(jq -r '.lease_comment_id' <<<"$CLAIM")"
assert_contains "lease comment id numeric" "n$LEASE_CID" "n"
if [[ "$LEASE_CID" =~ ^[0-9]+$ ]]; then
  pass "lease_comment_id shape"
else
  fail "lease_comment_id shape" "numeric" "$LEASE_CID"
fi

# 5. Renew.
RENEW="$(wit renew-lease "$ITEM1_ID" --lease-comment-id "$LEASE_CID")"
record "renew lease" "$RENEW"
assert_eq "renew keeps holder" "$(jq -r '.holder' <<<"$CLAIM")" "$(jq -r '.holder' <<<"$RENEW")"

# 6. Resolve + close item1 (resolution is a provider-native close; the seam has no
# close verb by design — skills resolve via their own flow).
N1="${ITEM1_ID##*#}"
gh issue close "$N1" -R "$REPO" --comment "e2e: resolved" >/dev/null

# 7. Graduation: item1's closure unblocks item2 (open-blocker count, NOT
# blockedBy.totalCount — closed blockers linger there).
FRONTIER2="$(wit list-frontier --repo "$REPO")"
record "frontier after item1 closed" "$FRONTIER2"
IDS2="$(jq -c '[.items[].id]' <<<"$FRONTIER2")"
assert_contains "item2 graduated into frontier" "$IDS2" "$ITEM2_ID"
assert_not_contains "closed item1 out of frontier" "$IDS2" "$ITEM1_ID"

# 8. Close out.
gh issue close "${ITEM2_ID##*#}" -R "$REPO" --comment "e2e: done" >/dev/null
gh issue close "${MAP_ID##*#}" -R "$REPO" --comment "e2e: map closed" >/dev/null

printf '\ne2e-probe: %d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
