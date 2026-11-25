#!/usr/bin/env bash
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
check-all.sh — re-check every tracked Claude-product GitHub issue's open/closed state.

Backend for `/known-issues check-all`.

Reads : <output-dir>/registry-snapshot.tsv  (number<TAB>repo<TAB>tracked_status)
Writes: <output-dir>/check-all-results.tsv  (+ check-all.log) next to the snapshot
Args  : --print-output-dir  create and print the resolved output directory, then
        exit. Run this FIRST and write the snapshot into the directory it names;
        the path is keyed, so it is not guessable from the plugin data root.
Env   : CHECK_ALL_OUTPUT_DIR  use this directory verbatim, unkeyed. An explicit
        caller override — keying is the caller's problem then.

Default output dir:
  <CLAUDE_PLUGIN_DATA>/check-all-output/<state-key>
  (CLAUDE_PLUGIN_DATA falls back to ~/.claude/plugins/data/harness-ops when the
  harness does not export it; <state-key> comes from lib/state-key.sh and is
  <repo-identity>/<worktree-discriminator>).

Exit  : 0  every row was attempted; a row whose lookup failed is a FETCH_FAILED
           row in the results file, not a failure of the run
        1  no snapshot in the output directory
        2  bad argument, gh or jq missing, or no output directory could be resolved
EOF
  exit 0
fi

PRINT_ONLY=0
if [[ "${1:-}" == "--print-output-dir" ]]; then
  PRINT_ONLY=1
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "ERROR: unknown argument: $1 (see --help)" >&2
  exit 2
fi

seg="${CLAUDE_PLUGIN_DATA:-}"
seg="${seg%[/\\]}"
seg="${seg##*[/\\]}"
if [[ "$seg" == harness-ops || "$seg" == harness-ops-* ]]; then
  DATA_DIR="$CLAUDE_PLUGIN_DATA"
else
  DATA_DIR="$HOME/.claude/plugins/data/harness-ops"
fi
COMPONENT_DIR="$DATA_DIR/check-all-output"

if [[ -n "${CHECK_ALL_OUTPUT_DIR:-}" ]]; then
  OUT_DIR="$CHECK_ALL_OUTPUT_DIR"
else
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  STATE_KEY="$(bash "$PLUGIN_ROOT/lib/state-key.sh")"
  if [[ -z "$STATE_KEY" ]]; then
    echo "ERROR: could not derive a state key ($PLUGIN_ROOT/lib/state-key.sh)" >&2
    exit 2
  fi
  OUT_DIR="$COMPONENT_DIR/$STATE_KEY"

  for legacy in registry-snapshot.tsv check-all-results.tsv check-all.log; do
    if [[ -f "$COMPONENT_DIR/$legacy" ]]; then
      echo "NOTE: unkeyed leftover from an older layout, not read: $COMPONENT_DIR/$legacy" >&2
    fi
  done
fi

mkdir -p "$OUT_DIR" || {
  echo "ERROR: could not create the output directory: $OUT_DIR" >&2
  exit 2
}

if [[ $PRINT_ONLY -eq 1 ]]; then
  printf '%s\n' "$OUT_DIR"
  exit 0
fi

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: $tool is required to re-check issues but is not on PATH" >&2
    exit 2
  }
done

SNAPSHOT="$OUT_DIR/registry-snapshot.tsv"
OUT="$OUT_DIR/check-all-results.tsv"
LOG="$OUT_DIR/check-all.log"

if [[ ! -f "$SNAPSHOT" ]]; then
  echo "ERROR: snapshot not found: $SNAPSHOT (run --print-output-dir, then write registry-snapshot.tsv into the directory it prints)" >&2
  exit 1
fi

: >"$LOG"
echo "number	repo	tracked_status	current_state	state_reason	closed_at	transition" >"$OUT"

n=0
total=$(grep -c '' "$SNAPSHOT" | tr -d '\r ')
while IFS=$'\t' read -r number repo tracked || [[ -n "$number" ]]; do
  n=$((n + 1))
  printf '[%d/%d] %s#%s ' "$n" "$total" "$repo" "$number" >>"$LOG"
  result=$(gh issue view "$number" --repo "$repo" --json state,stateReason,closedAt 2>>"$LOG")
  if [[ -z "$result" ]]; then
    echo "FETCH_FAILED" >>"$LOG"
    printf '%s\t%s\t%s\t\t\t\tFETCH_FAILED\n' "$number" "$repo" "$tracked" >>"$OUT"
    continue
  fi
  IFS=$'\x1f' read -r state reason closed < <(
    jq -r '[.state, .stateReason, .closedAt] | map(. // "") | join("\u001f")' <<<"$result" | tr -d '\r'
  )
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
