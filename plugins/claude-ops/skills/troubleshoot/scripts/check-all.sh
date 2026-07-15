#!/usr/bin/env bash
# Loop registry, query GitHub for current state, write transitions.
# Reads registry-snapshot.tsv (number<TAB>repo<TAB>tracked_status) from check-all-output/
# and writes check-all-results.tsv + check-all.log next to it.

# Omit -e: per-row gh failures are expected (rate-limit, deleted issues) and
# must not abort the loop — each row records its own FETCH_FAILED transition.
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
check-all.sh — re-check every tracked Claude-product GitHub issue's open/closed state.

Backend for `/troubleshoot check-all`.

Reads : check-all-output/registry-snapshot.tsv  (number<TAB>repo<TAB>tracked_status)
Writes: check-all-output/check-all-results.tsv  (+ check-all.log) next to the snapshot
Env   : CHECK_ALL_OUTPUT_DIR  override the output directory
        (default: <CLAUDE_PLUGIN_DATA>/check-all-output, falling back to
        ~/.claude/plugins/data/claude-ops/check-all-output when the harness
        does not export CLAUDE_PLUGIN_DATA)
EOF
  exit 0
fi

DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/claude-ops}"
OUT_DIR="${CHECK_ALL_OUTPUT_DIR:-$DATA_DIR/check-all-output}"
mkdir -p "$OUT_DIR"

SNAPSHOT="$OUT_DIR/registry-snapshot.tsv"
OUT="$OUT_DIR/check-all-results.tsv"
LOG="$OUT_DIR/check-all.log"

if [[ ! -f "$SNAPSHOT" ]]; then
  echo "ERROR: snapshot not found: $SNAPSHOT" >&2
  exit 1
fi

: >"$OUT"
: >"$LOG"
echo "number	repo	tracked_status	current_state	state_reason	closed_at	transition" >"$OUT"

n=0
total=$(wc -l <"$SNAPSHOT" | tr -d '\r ')
while IFS=$'\t' read -r number repo tracked; do
  n=$((n + 1))
  printf '[%d/%d] %s#%s ' "$n" "$total" "$repo" "$number" >>"$LOG"
  result=$(gh issue view "$number" --repo "$repo" --json state,stateReason,closedAt 2>>"$LOG")
  if [[ -z "$result" ]]; then
    echo "FETCH_FAILED" >>"$LOG"
    printf '%s\t%s\t%s\t\t\t\tFETCH_FAILED\n' "$number" "$repo" "$tracked" >>"$OUT"
    continue
  fi
  state=$(jq -r '.state // ""' <<<"$result" | tr -d '\r')
  reason=$(jq -r '.stateReason // ""' <<<"$result" | tr -d '\r')
  closed=$(jq -r '.closedAt // ""' <<<"$result" | tr -d '\r')
  if [[ "$tracked" == "open" && "$state" == "CLOSED" ]]; then
    transition="OPEN->CLOSED"
  elif [[ "$tracked" == "closed" && "$state" == "OPEN" ]]; then
    transition="CLOSED->OPEN"
  else
    transition="UNCHANGED"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$number" "$repo" "$tracked" "$state" "$reason" "$closed" "$transition" >>"$OUT"
  echo "$state $reason $transition" >>"$LOG"
done <"$SNAPSHOT"

echo "DONE" >>"$LOG"
