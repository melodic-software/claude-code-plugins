#!/usr/bin/env bash
# verify-claude-review-skill.sh — fail closed when the claude-review lane
# silently substitutes a manual diff review for /review:code-review (#3147).
#
# The reusable workflow concludes GREEN when the session as a whole succeeds,
# even if the Skill tool returned <error>Execute skill: review:code-review</error>
# and the agent wrote an ad hoc review instead. That check row staying green
# is the defect. This sibling job reads the posted review body (the
# deliverable, not the job log — see #2517) and reddens when the body reports
# that degrade as the reviewer's own process.
#
# READS THE POSTED REVIEW, NEVER THE JOB LOG. A log is not a contract: the
# reusable's outcome step source is echoed into the log and contains the
# skip phrases as string literals. The review body is what a reader sees.
#
# Environment:
#   GITHUB_EVENT_NAME    pull_request expected; anything else is not applicable
#   GITHUB_ACTOR         PR author login
#   SKIP_ACTORS          comma-separated actors exempt from review
#   LANE_RESULT          needs.review.result
#   GITHUB_REPOSITORY    owner/repo
#   PR_NUMBER            pull request number
#   EVENT_HEAD_SHA       the head SHA this run was triggered at
#   GH_TOKEN             token for the review-body read
#
# Exit: 0 evidence OK or not applicable; 1 silent skill-degrade detected.

set -euo pipefail

SKIP_ACTORS="${SKIP_ACTORS:-dependabot[bot],claude[bot],melodic-ai[bot],melodic-standards-sync[bot],cursor[bot]}"

usage() {
  cat <<'EOF'
verify-claude-review-skill.sh — guard against a green claude-review that never ran /review:code-review.

Reads the posted review body for this head. Exits 0 when the PR is exempt,
the lane skipped/cancelled/already-failed, or the review does not report a
Skill-tool degrade. Exits 1 when a successful lane posted a review that says
the Skill invocation failed and a manual review was substituted (#3147).
EOF
}

# fetch_review_bodies — review + issue-comment bodies on this PR. Defined as a
# function so the self-tests can substitute it without an API call.
fetch_review_bodies() {
  local repo="${GITHUB_REPOSITORY:?}" pr="${PR_NUMBER:?}"
  {
    gh api --paginate "repos/${repo}/pulls/${pr}/reviews" --jq '.[] | .body // empty'
    gh api --paginate "repos/${repo}/issues/${pr}/comments" --jq '.[] | .body // empty'
  }
}

# Process-language the degrade path writes about itself. A code review of this
# guard that quotes a single needle is not enough: both a skill-error report
# and a fallback report must be present in the same body. Prints `degrade` or
# `ok` so callers do not wrap the function in `if` / `||` (SC2310).
classify_silent_degrade() {
  local body="$1"
  local skill=0 fallback=0
  [[ "$body" == *'errored out in this environment'* ]] && skill=1
  [[ "$body" == *'Skill invocation errored'* ]] && skill=1
  [[ "$body" == *'<error>Execute skill:'* ]] && skill=1
  [[ "$body" == *'fell back'* ]] && fallback=1
  [[ "$body" == *'fallback'* ]] && fallback=1
  [[ "$body" == *'manual diff'* ]] && fallback=1
  [[ "$body" == *'manual-diff'* ]] && fallback=1
  if [[ "$skill" -eq 1 && "$fallback" -eq 1 ]]; then
    printf 'degrade\n'
  else
    printf 'ok\n'
  fi
}

main() {
  case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  *) ;;
  esac

  [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]] || {
    echo "not a pull_request event — guard not applicable"
    exit 0
  }

  if [[ ",${SKIP_ACTORS}," == *",${GITHUB_ACTOR:-},"* ]]; then
    echo "actor ${GITHUB_ACTOR} is skip-listed — guard not applicable"
    exit 0
  fi

  case "${LANE_RESULT:-}" in
  skipped)
    echo "review job skipped — guard not applicable"
    exit 0
    ;;
  cancelled)
    echo "review job cancelled — guard not applicable"
    exit 0
    ;;
  "")
    echo "ERROR: LANE_RESULT is empty — this guard is not wired to the review job, so it can determine nothing about it (#3147)" >&2
    exit 1
    ;;
  success) ;;
  *)
    echo "review job result=${LANE_RESULT} — lane already failed loudly; guard not applicable"
    exit 0
    ;;
  esac

  if [[ -z "${GITHUB_REPOSITORY:-}" || -z "${PR_NUMBER:-}" ]]; then
    echo "ERROR: GITHUB_REPOSITORY and PR_NUMBER are required to read the posted review (#3147)" >&2
    exit 1
  fi

  local bodies verdict
  # Assigned, not `cmd || fail`: an `||` / `if` around a function disables
  # `set -e` for its whole dynamic extent (SC2310; same split as
  # verify-security-review-evidence.sh).
  bodies="$(fetch_review_bodies)"
  verdict="$(classify_silent_degrade "$bodies")"
  case "$verdict" in
  degrade)
    echo "ERROR: claude-review posted a green review that reports a Skill-tool failure and a manual fallback. The maintained /review:code-review chain did not run (#3147)" >&2
    exit 1
    ;;
  ok) ;;
  *)
    echo "ERROR: classify_silent_degrade returned an unrecognised verdict: ${verdict}" >&2
    exit 1
    ;;
  esac

  echo "claude-review skill evidence OK (no silent Skill-tool fallback in posted review bodies)"
  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
