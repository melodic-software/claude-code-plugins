#!/usr/bin/env bash
# discover-prs.sh — deterministic PR discovery for the babysit loop.
#
# Implements the babysit "§5.0.2 PR discovery" filter as a script: lists OPEN
# PRs, drops drafts, returns oldest-first (lowest PR number first / FIFO).
# Dependabot and every other author are in scope (babysit covers all PR authors).
# Per babysit.md §5.0.2.
#
# The raw PR array is resolved from EITHER a fixture file (--prs-json, for
# offline tests / reuse) OR a live `gh pr list` call. The FILTER itself runs
# in this script body (NOT in `gh --jq`) so the fixture path exercises the
# exact same filter logic the live path does — that split is what makes the
# black-box test offline-capable.
#
# Owner/repo are NOT hardcoded: `gh pr list` auto-resolves the repository from
# the local git remote, so no -R flag or `gh repo view` round-trip is needed.
#
# Usage:
#   discover-prs.sh                         # live: gh pr list, then filter
#   discover-prs.sh --prs-json <file>       # offline: read raw array from file
#   discover-prs.sh --help
#
# Output (stdout): JSON array of {number,title,headRefName,isDraft,author}
#   objects, drafts + Dependabot removed, sorted ascending by number. Empty
#   discovery yields `[]`.
#
# Exit codes:
#   0  success (zero or more PRs emitted)
#   1  invalid argument or malformed input
#   2  gh api call failed
#   5  prerequisite missing (gh, jq)

set -uo pipefail # -e omitted: gh failure explicitly guarded with || { exit N }

PRS_JSON=""

usage() {
  sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --prs-json)
    if [[ $# -lt 2 ]]; then
      printf 'discover-prs: --prs-json requires an argument (use --help)\n' >&2
      exit 1
    fi
    PRS_JSON="$2"
    shift 2
    ;;
  -*)
    printf 'discover-prs: unknown flag %q (use --help)\n' "$1" >&2
    exit 1
    ;;
  *)
    printf 'discover-prs: unexpected argument %q (use --help)\n' "$1" >&2
    exit 1
    ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
have jq || {
  printf 'discover-prs: jq required\n' >&2
  exit 5
}

# --- Resolve raw PR array (fixture file OR live fetch) ------------------------

RAW=""
if [[ -n "$PRS_JSON" ]]; then
  if [[ ! -f "$PRS_JSON" ]]; then
    printf 'discover-prs: --prs-json file not found: %s\n' "$PRS_JSON" >&2
    exit 1
  fi
  RAW="$(cat "$PRS_JSON")"
else
  have gh || {
    printf 'discover-prs: gh CLI required\n' >&2
    exit 5
  }
  # No --jq here: the filter runs below so the fixture path tests the same
  # logic. Repo auto-resolved from the local git remote (no hardcode).
  RAW="$(gh pr list --state open --limit 200 \
    --json number,title,headRefName,isDraft,author 2>/dev/null)" || {
    printf 'discover-prs: gh pr list failed\n' >&2
    exit 2
  }
fi

# --- Validate input is an array, then filter ---------------------------------

if ! printf '%s' "$RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
  printf 'discover-prs: malformed PR JSON (expected an array)\n' >&2
  exit 1
fi

# Drop drafts only, sort oldest-first (lowest number first / FIFO). Dependabot
# and every other author are in scope — babysit ALL open PRs so CI-failing
# dependency PRs get diagnosed + fixed too, not just auto-merged. Empty discovery
# yields `[]` and exits 0. Mirrors babysit.md §5.0.2 verbatim.
if ! printf '%s' "$RAW" | jq '
  [.[]
    | select(.isDraft == false)]
  | sort_by(.number)
'; then
  printf 'discover-prs: jq failed filtering PR JSON\n' >&2
  exit 1
fi

exit 0
