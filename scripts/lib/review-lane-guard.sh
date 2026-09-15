# shellcheck shell=bash
# Shared entry gates for the two review-lane evidence guards. Sourced, never
# executed.
#
# scripts/verify-claude-review-skill.sh and
# scripts/verify-security-review-evidence.sh are siblings: each runs as a job
# beside its ci-workflows review lane and reddens when that lane reports green
# without evidence. Both open with the same gates, the SKIP_ACTORS default read,
# the pull_request event gate, the skip-listed-actor gate and the LANE_RESULT
# triage, and the SKIP_ACTORS value is exactly where the two drifted (2b4d8abf
# added cursor[bot] to both workflow lines and to only one of the guards). One
# definition here is one place for the next fix to land.
#
# WHAT THE CALLERS STILL OWN. Every string printed here and every exit code
# taken here is the CI lane contract, so the per-lane wording is data rather
# than a reason to keep a second copy of the block: the job name each message
# names, the issue the empty-LANE_RESULT failure cites, and what a guard says
# about a lane result it does not handle are arguments. Everything after the
# triage, the evidence read itself, differs completely between the two and stays
# in each guard.
#
# THE GATES EXIT RATHER THAN RETURN. A not-applicable pull request is a pass for
# the whole guard, and a caller that had to translate a return code back into
# that exit would be the second copy again. Call them as plain statements: a
# function called from `if` / `&&` / `||` runs its whole body with errexit off
# (ShellCheck SC2310, enabled on purpose in this repository's `.shellcheckrc`).

# The default is the ratified list in .github/claude-skip-actors, read through
# its one parser, never a restated literal. Read at SOURCE time, which is where
# each guard read it, so `--help` and `main` see the same value.
if [[ -z "${SKIP_ACTORS:-}" ]]; then
  SKIP_ACTORS="$("$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/read-skip-actors.sh")" || exit 2
fi

# review_lane_guard::require_pull_request_event
#
# Exits 0 on any other event: there is no pull request for a review lane to have
# produced evidence about.
review_lane_guard::require_pull_request_event() {
  [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]] || {
    echo "not a pull_request event — guard not applicable"
    exit 0
  }
}

# review_lane_guard::require_unskipped_actor
#
# Exits 0 when the author is on the ratified skip list, whose pull requests the
# review lanes do not review in the first place.
review_lane_guard::require_unskipped_actor() {
  if [[ ",${SKIP_ACTORS}," == *",${GITHUB_ACTOR:-},"* ]]; then
    echo "actor ${GITHUB_ACTOR} is skip-listed — guard not applicable"
    exit 0
  fi
}

# review_lane_guard::triage_lane_result <lane> <issue> <other-result-note>
#
# Returns only on `success`, the one lane result that leaves anything for a
# guard to check; every other value exits here.
#
# <lane> names the job in each message, <issue> is what the empty-LANE_RESULT
# failure cites, and <other-result-note> is what this lane says about a result it
# does not handle itself.
#
# `needs.<job>.result` is populated on every outcome, so an empty value means
# the guard is not wired to the lane at all. It cannot determine anything, and a
# guard that passes on uncertainty reports safety it did not check.
review_lane_guard::triage_lane_result() {
  local lane="$1" issue="$2" other_result_note="$3"
  case "${LANE_RESULT:-}" in
  skipped)
    echo "${lane} job skipped — guard not applicable"
    exit 0
    ;;
  cancelled)
    echo "${lane} job cancelled — guard not applicable"
    exit 0
    ;;
  "")
    echo "ERROR: LANE_RESULT is empty — this guard is not wired to the ${lane} job, so it can determine nothing about it (${issue})" >&2
    exit 1
    ;;
  success) ;;
  *)
    echo "${lane} job result=${LANE_RESULT} — ${other_result_note}"
    exit 0
    ;;
  esac
}
