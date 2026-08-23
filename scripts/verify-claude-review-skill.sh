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
#   EVENT_HEAD_SHA       the head SHA this run was triggered at (required)
#   REVIEWER_LOGINS      comma-separated logins whose reviews count
#                        (default: claude[bot])
#   GH_TOKEN             token for the review-body read
#
# Exit: 0 evidence OK or not applicable; 1 silent skill-degrade detected.

set -euo pipefail

SKIP_ACTORS="${SKIP_ACTORS:-dependabot[bot],claude[bot],melodic-ai[bot],melodic-standards-sync[bot],cursor[bot]}"
REVIEWER_LOGINS="${REVIEWER_LOGINS:-claude[bot]}"

usage() {
  cat <<'EOF'
verify-claude-review-skill.sh — guard against a green claude-review that never ran /review:code-review.

Reads the posted review body for this head. Exits 0 when the PR is exempt,
the lane skipped/cancelled/already-failed, or the review does not report a
Skill-tool degrade. Exits 1 when a successful lane posted a review that says
the Skill invocation failed and a manual review was substituted (#3147).
EOF
}

# fetch_review_bodies — one base64 body per line, reviews only. Defined as a
# function so the self-tests can substitute it without an API call.
#
# Issue comments are not evidence: any account can comment on a public PR and
# trip a fail-closed substring guard. Older reviews at a prior head are not
# evidence either — a corrected push must be judged by the review posted for
# this EVENT_HEAD_SHA. REVIEWER_LOGINS defaults to the lane's bot.
fetch_review_bodies() {
  local repo="${GITHUB_REPOSITORY:?}" pr="${PR_NUMBER:?}"
  local sha="${EVENT_HEAD_SHA:?}"
  local allow="${REVIEWER_LOGINS:-claude[bot]}"
  # shellcheck disable=SC2016  # the jq program is literal; $sha/$allow bind via --arg
  gh api --paginate "repos/${repo}/pulls/${pr}/reviews" \
    --jq --arg sha "$sha" --arg allow "$allow" '
      ($allow | split(",") | map(gsub("^[ \t]+|[ \t]+$";"")) | map(select(length > 0))) as $logins
      | .[]
      | select((.commit_id // "") == $sha)
      | select(.user.login as $u | ($logins | index($u)) != null)
      | (.body // "")
      | @base64
    '
}

# decode_review_body — GNU `base64 -d`, BSD `base64 -D`. Prints the decoded
# body on stdout. A failed decode yields empty (classified as `ok`).
decode_review_body() {
  local encoded="$1" body=""
  body="$(printf '%s' "$encoded" | base64 -d 2>/dev/null)" || body="$(printf '%s' "$encoded" | base64 -D 2>/dev/null)" || body=""
  printf '%s' "$body"
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

  if [[ -z "${EVENT_HEAD_SHA:-}" ]]; then
    echo "ERROR: EVENT_HEAD_SHA is empty — this guard cannot tell which reviews belong to this run, so it can determine nothing about it (#3147)" >&2
    exit 1
  fi

  # Assigned, not `cmd || fail`: an `||` / `if` around a function disables
  # `set -e` for its whole dynamic extent (SC2310; same split as
  # verify-security-review-evidence.sh).
  local encoded body verdict
  local records
  records="$(fetch_review_bodies)"
  while IFS= read -r encoded || [[ -n "${encoded}" ]]; do
    [[ -n "${encoded}" ]] || continue
    body="$(decode_review_body "$encoded")"
    verdict="$(classify_silent_degrade "$body")"
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
  done <<<"$records"

  echo "claude-review skill evidence OK (no silent Skill-tool fallback in posted review bodies)"
  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
