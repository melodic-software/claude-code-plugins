#!/usr/bin/env bash
# Loop registry, query GitHub for current state, write transitions.
# Reads registry-snapshot.tsv (number<TAB>repo<TAB>tracked_status) from the
# resolved output directory and writes check-all-results.tsv + check-all.log
# next to it.
#
# The output directory is KEYED by project. ${CLAUDE_PLUGIN_DATA} resolves to
# ~/.claude/plugins/data/{id}/ and carries no project, checkout or worktree
# segment, so a fixed `check-all-output/` is one scratch directory per MACHINE.
# The registry this script reports on is per-project whenever the operator sets
# the `registry_dir` option, so an unkeyed scratch directory lets one project's
# snapshot be overwritten by another's and then reports the second project's
# rows as the first's. That is a wrong answer served, not merely a lost file.
# The key comes from lib/state-key.sh, the scheme
# docs/conventions/plugin-data-report-keying/ rule 1 defines. It splits
# worktrees, which is right here: registry_dir is project-relative, so two
# worktrees of one repository hold two registries.
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
  (CLAUDE_PLUGIN_DATA falls back to ~/.claude/plugins/data/claude-ops when the
  harness does not export it; <state-key> comes from lib/state-key.sh and is
  <repo-identity>/<worktree-discriminator>).
EOF
  exit 0
fi

PRINT_ONLY=0
if [[ "${1:-}" == "--print-output-dir" ]]; then
  PRINT_ONLY=1
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "ERROR: unknown argument: $1" >&2
  exit 2
fi

DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/claude-ops}"
COMPONENT_DIR="$DATA_DIR/check-all-output"

if [[ -n "${CHECK_ALL_OUTPUT_DIR:-}" ]]; then
  OUT_DIR="$CHECK_ALL_OUTPUT_DIR"
else
  # Resolved from this file, never from an inherited CLAUDE_PLUGIN_ROOT: a
  # subprocess can carry another plugin's value for that variable.
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  STATE_KEY="$(bash "$PLUGIN_ROOT/lib/state-key.sh")"
  # Fail closed. Falling back to the unkeyed path is the defect being fixed:
  # it would silently reintroduce the cross-project collision.
  if [[ -z "$STATE_KEY" ]]; then
    echo "ERROR: could not derive a state key ($PLUGIN_ROOT/lib/state-key.sh)" >&2
    exit 2
  fi
  OUT_DIR="$COMPONENT_DIR/$STATE_KEY"

  # Rule 3 — an artifact written under the old unkeyed layout has no project
  # segment, so nothing records which repository produced it. Name it; never
  # read it, move it, or compute from it.
  for legacy in registry-snapshot.tsv check-all-results.tsv check-all.log; do
    if [[ -f "$COMPONENT_DIR/$legacy" ]]; then
      echo "NOTE: unkeyed leftover from an older layout, not read: $COMPONENT_DIR/$legacy" >&2
    fi
  done
fi

mkdir -p "$OUT_DIR"

if [[ $PRINT_ONLY -eq 1 ]]; then
  printf '%s\n' "$OUT_DIR"
  exit 0
fi

SNAPSHOT="$OUT_DIR/registry-snapshot.tsv"
OUT="$OUT_DIR/check-all-results.tsv"
LOG="$OUT_DIR/check-all.log"

if [[ ! -f "$SNAPSHOT" ]]; then
  echo "ERROR: snapshot not found: $SNAPSHOT" >&2
  exit 1
fi

: >"$LOG"
echo "number	repo	tracked_status	current_state	state_reason	closed_at	transition" >"$OUT"

n=0
# wc -l counts newlines, not rows: a final row without a trailing newline would
# be undercounted here and then dropped by the read loop below without the
# `|| [[ -n "$number" ]]` guard, which lets read's last (newline-less) partial
# read still populate $number before the loop exits.
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
