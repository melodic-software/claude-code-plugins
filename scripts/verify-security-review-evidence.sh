#!/usr/bin/env bash
# verify-security-review-evidence.sh — fail-closed guard for the required
# security-review check when an in-scope PR reports success without execution
# evidence (#2337).
#
# The ci-workflows reusable deliberately reports GREEN on some infra-failure
# classes; this script is a repo-owned supplement that catches the subset the
# issue filed: an in-scope PR whose security-review job concluded success while
# nothing was actually reviewed.
#
# READS THE LANE'S DECLARED VERDICT, NEVER ITS LOG. The reusable classifies
# every attempt and surfaces the result as workflow_call outputs
# from ci-workflows v0.14.2 onward; this guard consumes those. A log is not a
# contract: the lane's `Report review outcome` step is an inline github-script
# whose SOURCE is echoed into that same log and contains the skip phrases as
# string literals, so a log grep would match every successful in-scope pull
# request and redden exactly the ones the guard exists to approve, and log
# text is pinned by no test upstream. Do not reintroduce a log read.
#
# Scope is the lane's own `relevant` output, never a second implementation of
# the same matcher: two matchers (say, `fnmatch` semantics against the lane's
# `git check-ignore` gitignore semantics) disagree on exactly the patterns
# that distinguish them. One matcher, upstream.
#
# Runs as a sibling job after security-review in
# .github/workflows/claude-security-review.yml, which supplies the LANE_* values
# from `needs.security-review`.
#
# Environment:
#   GITHUB_EVENT_NAME    pull_request expected; anything else is not applicable
#   GITHUB_ACTOR         PR author login
#   SKIP_ACTORS          comma-separated actors exempt from review
#   LANE_RESULT          needs.security-review.result
#   LANE_RELEVANT        the lane's `relevant` output
#   LANE_REVIEW_RAN      the lane's `review-ran` output
#   LANE_REVIEW_FAILED   the lane's `review-failed` output
#   LANE_FAILURE_CLASS   the lane's `failure-class` output (message text only)
#   GITHUB_REPOSITORY    owner/repo — only read on the no-verdict path
#   PR_NUMBER            pull request number — only read on the no-verdict path
#   EVENT_HEAD_SHA       the head SHA this run was triggered at
#   GH_TOKEN             token for the one API read on the no-verdict path
#
# Exit: 0 evidence OK or not applicable; 1 in-scope false pass detected.

set -euo pipefail

SKIP_ACTORS="${SKIP_ACTORS:-dependabot[bot],claude[bot],melodic-ai[bot],melodic-standards-sync[bot]}"

usage() {
  cat <<'EOF'
verify-security-review-evidence.sh — guard against in-scope security-review false passes.

Reads the security-review lane's DECLARED outputs from the environment. Exits 0
when the PR is out of scope, exempt, skipped, or the lane declares that a review
ran. Exits 1 when an in-scope lane concluded success while declaring that no
review happened, and when the lane declares no verdict at all at a head that has
not moved (#2337).
EOF
}

# live_head_sha — the pull request's current head, for the ONE case that needs
# it: telling a retired superseded run apart from a genuinely absent verdict.
# Defined as a function so the self-tests can substitute it without an API call.
live_head_sha() {
  gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq '.head.sha'
}

# classify_absent_verdict
#
# The lane declares nothing when its steps never reached the outcome composite.
# Exactly one legitimate cause exists: the lane's freshness guard retired the
# run because the head moved on, and the newer head's run reports in its place.
# Every other cause — a caller pinned to a release older than the
# declared-output contract, or a lane shape that stopped forwarding — is a
# guard that has gone blind, and a blind security guard must not report safety.
#
# Prints the VERDICT on stdout — `retired` or `blind` — and reserves a non-zero
# EXIT for a genuine fault. The explanation goes to stderr so it cannot be
# mistaken for the verdict. Calling
# this from an `if` instead would disable `set -e` for its whole dynamic extent
# (ShellCheck SC2310, enabled on purpose in this repository's `.shellcheckrc`),
# which is how a fault inside a helper stops being a fault.
classify_absent_verdict() {
  if [[ -z "${GITHUB_REPOSITORY:-}" || -z "${PR_NUMBER:-}" || -z "${EVENT_HEAD_SHA:-}" ]]; then
    echo "ERROR: security-review declared no verdict and this guard cannot tell whether the head moved (GITHUB_REPOSITORY, PR_NUMBER, and EVENT_HEAD_SHA are all required to decide) — refusing to report evidence it did not check (#2337)" >&2
    printf 'blind\n'
    return 0
  fi
  local head
  head="$(live_head_sha)"
  if [[ -z "$head" ]]; then
    echo "ERROR: security-review declared no verdict and the live head could not be read, so a retired superseded run cannot be ruled out — refusing to report evidence it did not check (#2337)" >&2
    printf 'blind\n'
    return 0
  fi
  if [[ "$head" != "$EVENT_HEAD_SHA" ]]; then
    echo "security-review declared no verdict and the head has moved (${EVENT_HEAD_SHA} -> ${head}) — this run was retired as superseded and the newer head's run reports instead; guard not applicable" >&2
    printf 'retired\n'
    return 0
  fi
  echo "ERROR: in-scope security-review concluded success but declared NO verdict at the current head — the caller's ci-workflows pin predates the declared-output contract (ci-workflows v0.14.2), the lane stopped forwarding it, or the lane's relevance gate hard-errored on a rejected \`!\` / \`?\` / \`+\` pattern in .github/claude-security-paths and took its outputs down with it. Check the lane's own annotations for which; do not wave this through (#2337)" >&2
  printf 'blind\n'
  return 0
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

  # A skipped lane job is one of the four no-verdict paths the lane documents —
  # out of scope, a fork PR, a skip-listed actor, or either kill-switch. None is
  # something this PR can act on, and the lane's own contract makes each a
  # name-stable skip a required-check ruleset reads as success.
  case "${LANE_RESULT:-}" in
    skipped)
      echo "security-review job skipped — guard not applicable"
      exit 0
      ;;
    cancelled)
      echo "security-review job cancelled — guard not applicable"
      exit 0
      ;;
    "")
      # `needs.<job>.result` is populated on every outcome, so an empty value
      # means this guard is not wired to the lane at all. It cannot determine
      # anything, and a guard that passes on uncertainty reports safety it did
      # not check.
      echo "ERROR: LANE_RESULT is empty — this guard is not wired to the security-review job, so it can determine nothing about it (#2337)" >&2
      exit 1
      ;;
    success) ;;
    *)
      echo "security-review job result=${LANE_RESULT} — deferring to job status"
      exit 0
      ;;
  esac

  if [[ "${LANE_RELEVANT:-}" == "false" ]]; then
    echo "diff does not touch security-relevant paths — guard not applicable"
    exit 0
  fi

  case "${LANE_REVIEW_RAN:-}" in
    true)
      echo "security-review evidence OK (the lane declares a review ran, in-scope)"
      exit 0
      ;;
    false)
      if [[ "${LANE_REVIEW_FAILED:-}" == "true" ]]; then
        # The lane rules this GREEN on purpose: the cause is outside this PR's
        # and the org's control, and a required context that reddens on a
        # provider outage locks every merge for the length of it. This guard
        # exists to catch a FALSE pass, not to overturn that ruling — so it
        # says loudly that nothing was reviewed and defers.
        echo "::warning::security-review was in scope and did not complete (class=${LANE_FAILURE_CLASS:-unknown}). Nothing was reviewed at this head, and the lane reports green by contract. A human should review the security-sensitive changes here before merging."
        exit 0
      fi
      echo "ERROR: in-scope security-review concluded success but declares that no review ran and no failure occurred — the action skipped itself (workflow-validation skip: the caller's workflow file must match the default branch's copy). Merging the caller-workflow change clears it; a re-run cannot (#2337)" >&2
      exit 1
      ;;
    *)
      # A command substitution, so `set -e` stays live for the helper and a
      # genuine fault inside it still aborts the guard, while the verdict
      # travels on stdout where it cannot be confused with one. An
      # unrecognised verdict is a fault, never a pass.
      local absent_verdict
      absent_verdict="$(classify_absent_verdict)"
      case "$absent_verdict" in
        retired) exit 0 ;;
        blind) exit 1 ;;
        *)
          echo "ERROR: the absent-verdict classifier returned an unrecognised verdict: ${absent_verdict}" >&2
          exit 1
          ;;
      esac
      ;;
  esac
}

# Sourced by the self-tests, which substitute live_head_sha; executed in CI.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
