#!/usr/bin/env bash
# backfill-capability-tier-labels.sh — one-shot migration for #1716 body stamps.
#
# Finds open items whose body carries a legacy frontier-tier triage-briefing signal
# but lack the provider-permissioned capability-tier: frontier label, then optionally
# applies the label. Triage refuses to re-triage already-triaged output, so setup
# apply runs this pass after the label axis is provisioned.
#
# Usage:
#   backfill-capability-tier-labels.sh check [--repo <owner>/<repo>]
#   backfill-capability-tier-labels.sh apply [--repo <owner>/<repo>] [--dry-run] [--yes]
#
# check — prints one candidate issue/PR number per line (stdout); exit 0 always.
# apply — adds capability-tier: frontier to each candidate; exit 1 when label missing
#         from repo or gh unavailable; exit 2 when interactive confirmation declined.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
# shellcheck source=lib/legacy-frontier-tier-signal.sh
source "$LIB_DIR/legacy-frontier-tier-signal.sh"

CAPABILITY_TIER_LABEL='capability-tier: frontier'
MODE="${1:-}"
shift || true

REPO=""
DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

repo_args=()
if [[ -n "$REPO" ]]; then
  repo_args=(-R "$REPO")
fi

require_gh() {
  command -v gh >/dev/null 2>&1 || {
    echo "ERROR: gh required for backfill" >&2
    exit 1
  }
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq required for backfill" >&2
    exit 1
  }
}

label_exists_in_repo() {
  require_gh
  gh label list "${repo_args[@]}" --limit 200 --json name \
    | jq -e --arg want "$CAPABILITY_TIER_LABEL" '[.[] | .name] | index($want) != null' >/dev/null
}

item_has_capability_tier_label() {
  local labels_json="$1"
  jq -e --arg want "$CAPABILITY_TIER_LABEL" \
    '[.[] | .name] | index($want) != null' <<<"$labels_json" >/dev/null 2>&1
}

list_open_items_without_label_json() {
  require_gh
  local items
  items="$(gh issue list "${repo_args[@]}" --state open \
    --json number,title,body,labels \
    --limit 1000 | tr -d '\r')"

  jq -c --arg label "$CAPABILITY_TIER_LABEL" '
    [.[] |
      select(
        ([.labels[]?.name] | index($label) == null)
        and (.body != null)
      )
    ]' <<<"$items"
}

filter_legacy_candidates() {
  local items_json="$1"
  jq -c '.[]' <<<"$items_json" | while IFS= read -r item; do
    local body labels_json number
    body="$(jq -r '.body // ""' <<<"$item")"
    labels_json="$(jq -c '.labels // []' <<<"$item")"
    number="$(jq -r '.number' <<<"$item")"
    item_has_capability_tier_label "$labels_json"
    if (( $? == 0 )); then
      continue
    fi
    wit_body_has_legacy_frontier_tier_signal "$body"
    if (( $? == 0 )); then
      printf '%s\n' "$number"
    fi
  done
}

usage() {
  cat <<EOF
Usage:
  backfill-capability-tier-labels.sh check [--repo <owner>/<repo>]
  backfill-capability-tier-labels.sh apply [--repo <owner>/<repo>] [--dry-run] [--yes]
EOF
}

case "$MODE" in
  check)
    items="$(list_open_items_without_label_json)"
    filter_legacy_candidates "$items"
    ;;
  apply)
    label_exists_in_repo
    if (( $? != 0 )); then
      echo "ERROR: $CAPABILITY_TIER_LABEL is not provisioned in the repository label set" >&2
      echo "Run /work-items:setup apply to provision the label axis first, or route to the label-as-code owner." >&2
      exit 1
    fi
    mapfile -t candidates < <(items="$(list_open_items_without_label_json)"; filter_legacy_candidates "$items")
    if [[ "${#candidates[@]}" -eq 0 ]]; then
      echo "No legacy frontier-tier body stamps need backfill."
      exit 0
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'Would apply %s to issue(s): %s\n' "$CAPABILITY_TIER_LABEL" "${candidates[*]}"
      exit 0
    fi
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      echo "Apply $CAPABILITY_TIER_LABEL to ${#candidates[@]} item(s): ${candidates[*]}?"
      read -r -p "Proceed? [y/N] " reply
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted." >&2; exit 2 ;;
      esac
    fi
    for number in "${candidates[@]}"; do
      gh issue edit "$number" "${repo_args[@]}" --add-label "$CAPABILITY_TIER_LABEL"
      echo "Applied $CAPABILITY_TIER_LABEL to #$number"
    done
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
