#!/usr/bin/env bash
# Resolve the `--write` report path for /claude-ops:observability.
#
# WHY THIS IS A SCRIPT AND NOT A SENTENCE. ${CLAUDE_PLUGIN_DATA} resolves to
# ~/.claude/plugins/data/{id}/, keyed to the plugin identifier and nothing else
# (plugins reference, § Persistent data directory). The report used to be
# written to `reports/claude-observability-<date>.md`, which is one file per
# MACHINE per day: every project the operator ran the skill in on that date
# wrote the same path, and the last run silently replaced the others. The
# report is project-local by construction: its source is the hook event log
# under the project-relative `session_event_log_dir` (default
# `.observability/claude`), so the path has to carry project identity.
#
# The key is lib/state-key.sh, the scheme defined by
# docs/conventions/plugin-data-report-keying/ rule 1:
#
#   ${CLAUDE_PLUGIN_DATA}/reports/<state-key>/claude-observability-<date>.md
#
# <state-key> = <repo-identity>/<worktree-discriminator>. It SPLITS worktrees,
# which is what this artifact needs: the hook event log lives inside the
# checkout, so two worktrees of one repository produce two different reports
# and must not share a path.
#
# Rule 3: a report written under the old unkeyed layout has no project
# segment, so nothing records which repository produced it. This script names
# such a leftover on stderr and never reads, moves, or derives from it.
#
# Retention is unchanged and deliberate: one file per project per DATE, so a
# same-day rerun of the same project still replaces its own earlier report. The
# report is a working artifact, not a trend series.
#
# Usage:
#   report-path.sh [--root <path>] [--date YYYY-MM-DD] [--mkdir] [--explain]
#
#   --root <path>  derive the key for that directory instead of the current one
#   --date <date>  use that date instead of today (UTC-naive, local `date`)
#   --mkdir        create the parent directory before printing
#   --explain      write the state-key rung and its inputs to stderr
#
# Exit: 0 on a derivation; 2 on a bad argument or an underivable state key.

set -uo pipefail

usage() {
  cat <<'EOF'
report-path.sh: resolve the keyed `--write` report path for /claude-ops:observability.

Prints ${CLAUDE_PLUGIN_DATA}/reports/<state-key>/claude-observability-<date>.md

Usage:
  report-path.sh [--root <path>] [--date YYYY-MM-DD] [--mkdir] [--explain] [--help]

  --root <path>  derive the key for that directory instead of the current one
  --date <date>  use that date instead of today
  --mkdir        create the parent directory before printing
  --explain      write the state-key rung and its inputs to stderr

Exit: 0 on a derivation; 2 on a bad argument or an underivable state key.
EOF
}

ROOT_ARG=""
DATE_ARG=""
DO_MKDIR=0
EXPLAIN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --root needs a path" >&2
      exit 2
    fi
    ROOT_ARG="$2"
    shift 2
    ;;
  --date)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --date needs a YYYY-MM-DD value" >&2
      exit 2
    fi
    DATE_ARG="$2"
    shift 2
    ;;
  --mkdir)
    DO_MKDIR=1
    shift
    ;;
  --explain)
    EXPLAIN=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

REPORT_DATE="${DATE_ARG:-$(date +%Y-%m-%d)}"
# The date becomes a FILENAME component. Reject anything that is not the shape
# the scheme means, so `--date ../../etc/x` cannot walk the report out of the
# plugin's namespace.
if [[ ! "$REPORT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "ERROR: --date must be YYYY-MM-DD: $REPORT_DATE" >&2
  exit 2
fi

# Resolved from this file, never from an inherited CLAUDE_PLUGIN_ROOT: a
# subprocess can carry another plugin's value for that variable.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STATE_KEY_SH="$PLUGIN_ROOT/lib/state-key.sh"

key_args=()
[[ -n "$ROOT_ARG" ]] && key_args+=(--root "$ROOT_ARG")
[[ $EXPLAIN -eq 1 ]] && key_args+=(--explain)

STATE_KEY="$(bash "$STATE_KEY_SH" "${key_args[@]+"${key_args[@]}"}")"
# Fail closed. Falling back to the unkeyed path is the defect being fixed.
if [[ -z "$STATE_KEY" ]]; then
  echo "ERROR: could not derive a state key ($STATE_KEY_SH)" >&2
  exit 2
fi

DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/claude-ops}"
COMPONENT_DIR="$DATA_DIR/reports"
REPORT_DIR="$COMPONENT_DIR/$STATE_KEY"

# Rule 3: name the unattributable leftovers, read none of them.
if [[ -d "$COMPONENT_DIR" ]]; then
  for legacy in "$COMPONENT_DIR"/claude-observability-*.md; do
    [[ -f "$legacy" ]] || continue
    echo "NOTE: unkeyed leftover from an older layout, not read: $legacy" >&2
  done
fi

if [[ $DO_MKDIR -eq 1 ]]; then
  mkdir -p "$REPORT_DIR" || exit 2
fi

printf '%s/claude-observability-%s.md\n' "$REPORT_DIR" "$REPORT_DATE"
