#!/usr/bin/env bash
# probe-observability-state.sh — report local telemetry-store state for the
# observability skill's `## Pre-computed context` block.
#
# Two of that block's lines are real shell work — a repo-root-or-working-directory
# default, an env override, a per-file size loop — and a pre-compute line carrying
# genuine shell expansion (`$f`, `$d`, `${VAR:-default}`, `$(…)`) is refused by the
# worktree-isolation guard, so the whole skill fails to load when invoked from an
# isolated agent (#1687). Both lines therefore call this script through
# `${CLAUDE_PLUGIN_ROOT}`, which the harness substitutes into a literal path before
# any shell sees it.
#
# One script, two modes rather than two scripts: both lines read the same local
# observability tree, so they are two facets of one probe surface, and a caller
# picking a mode is the only difference between them.
#
# Usage:
#   probe-observability-state.sh --hook-events
#   probe-observability-state.sh --otel-store
#
# --hook-events output (stdout, exactly one line) over
# <store root>/.claude/observability/hook-events.jsonl:
#   <N> events
#   EMPTY (no hook-event emitter wired, or no hooks fired yet)
#
# --otel-store output (stdout, three lines — one per store file, in order
# cc-logs.json, cc-metrics.json, cc-traces.json):
#   <name>:<bytes>B
#   <name>:absent
#
# Store resolution, unchanged from the lines this replaced:
#   --hook-events  <git toplevel, or the working directory when not inside a
#                  repo>/.claude/observability/hook-events.jsonl — no env override,
#                  matching the line it replaces.
#   --otel-store   CC_OTEL_STORE when set and non-empty, used verbatim; otherwise
#                  <git toplevel, or the working directory>/.claude/observability/otel.
#
# The git toplevel is CR-stripped through an empty-means-fall-back test rather than
# a `|| pwd` continuation, because piping through `tr` would make the pipeline
# always succeed and swallow the not-in-a-repo fallback. `wc` output is emitted
# as captured, exactly as the pre-compute lines did.
#
# Exit codes:
#   0  the requested mode's lines were emitted
#   3  invalid, missing, or conflicting argument

set -uo pipefail

err() { printf 'ERROR: %s\n' "$*" >&2; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

MODE=""
while (($#)); do
  case "$1" in
  --hook-events | --otel-store)
    if [[ -n "$MODE" ]]; then
      err "modes are mutually exclusive: $MODE and $1"
      exit 3
    fi
    MODE="$1"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown argument: $1"
    exit 3
    ;;
  esac
done

if [[ -z "$MODE" ]]; then
  err "a mode is required: --hook-events or --otel-store"
  exit 3
fi

repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$PWD"
  fi
}

case "$MODE" in
--hook-events)
  HOOK_LOG="$(repo_root)/.claude/observability/hook-events.jsonl"
  if [[ -f "$HOOK_LOG" ]]; then
    printf '%s events\n' "$(wc -l <"$HOOK_LOG")"
  else
    printf 'EMPTY (no hook-event emitter wired, or no hooks fired yet)\n'
  fi
  ;;
--otel-store)
  STORE="${CC_OTEL_STORE:-$(repo_root)/.claude/observability/otel}"
  for name in cc-logs.json cc-metrics.json cc-traces.json; do
    if [[ -f "$STORE/$name" ]]; then
      printf '%s:%sB\n' "$name" "$(wc -c <"$STORE/$name" 2>/dev/null || echo 0)"
    else
      printf '%s:absent\n' "$name"
    fi
  done
  ;;
*)
  err "unhandled mode: $MODE"
  exit 3
  ;;
esac
