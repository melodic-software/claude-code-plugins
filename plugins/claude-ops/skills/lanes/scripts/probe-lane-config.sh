#!/usr/bin/env bash
# probe-lane-config.sh — report where the lane config resolves to and whether it exists.
#
# One line of the lanes skill's `## Pre-computed context` block. Resolving it is
# real shell work — an env override, a repo-root-or-working-directory default, a
# jq count — and a pre-compute line carrying genuine shell expansion (`$c`,
# `${VAR:-default}`, `$(…)`) is refused by the worktree-isolation guard, so the
# whole skill fails to load when invoked from an isolated agent (#1687). The
# logic therefore lives here and the skill invokes the script through
# `${CLAUDE_PLUGIN_ROOT}`, which the harness substitutes into a literal path
# before any shell sees it.
#
# Usage:
#   probe-lane-config.sh
#
# Output (stdout, exactly one line):
#   <path> (<N> lanes)  config present; N is `(.lanes//[])|length` over it
#   <path> ( lanes)     config present but the count is unavailable — jq missing,
#                       or the file is not readable as JSON. The count degrades to
#                       empty rather than erroring (the `2>/dev/null` inside the
#                       count substitution).
#   absent (<path>) — author one (see context/config.md)
#
# Path resolution:
#   CLAUDE_OPS_LANES_CONFIG when set and non-empty — used verbatim, no suffix
#   appended; otherwise <git toplevel, or the working directory when not inside a
#   repo>/.work/lanes.json.
#
# The jq count is CR-stripped per this directory's standing convention (see
# machine-behavior.sh): some native-Windows jq builds CRLF-terminate their output
# and `$(…)` strips only the trailing LF, leaving a stray CR inside the reported
# count. The git toplevel is CR-stripped through an empty-means-fall-back test
# rather than a `|| pwd` continuation, because piping through `tr` would make the
# pipeline always succeed and swallow the not-in-a-repo fallback.
#
# Exit codes:
#   0  a line was emitted (either state)
#   3  invalid argument

set -uo pipefail

err() { printf 'ERROR: %s\n' "$*" >&2; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

while (($#)); do
  case "$1" in
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

repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$PWD"
  fi
}

CONFIG="${CLAUDE_OPS_LANES_CONFIG:-$(repo_root)/.work/lanes.json}"

if [[ -f "$CONFIG" ]]; then
  printf '%s (%s lanes)\n' "$CONFIG" "$(jq -r '(.lanes//[])|length' "$CONFIG" 2>/dev/null | tr -d '\r')"
else
  printf 'absent (%s) — author one (see context/config.md)\n' "$CONFIG"
fi
