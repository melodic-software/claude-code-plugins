#!/usr/bin/env bash
# test-scope: .github/standards/runner-policy/package.json
# Contract test for check-claude-secrets-environment.sh; each expected finding
# comes from the rule text, not the checker's output:
# https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#claude-secrets
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-claude-secrets-environment.sh"
SUT_MJS="$SCRIPT_DIR/check-claude-secrets-environment.mjs"
POLICY_DIR="$SCRIPT_DIR/../.github/standards/runner-policy"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

WF=.github/workflows

remote_call() {
  local trigger="${3:-workflow_dispatch}" with=""
  [[ -n "${4:-}" ]] && with="    with:\n      environment: $4\n"
  # shellcheck disable=SC2016  # a literal workflow expression, never expanded
  printf "on: %s\njobs:\n  %s:\n    uses: melodic-software/ci-workflows/.github/workflows/x.yml@main\n${with}"'    secrets:\n      CLAUDE_API_KEY: ${{ secrets.REVIEWS_CLAUDE_API_KEY }}\n' "$trigger" "$2" >"$WF/$1"
}

mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --sut "$SUT_MJS" --label claude-secrets-environment || return 1
  dir="${!1}"
  mkdir -p "$dir/$WF" "$dir/.github/standards/runner-policy"
  cp "$POLICY_DIR/package.json" "$dir/.github/standards/runner-policy/"
  ln -s "$POLICY_DIR/node_modules" "$dir/.github/standards/runner-policy/node_modules"
  (
    cd "$dir" || exit 1
    remote_call intake-triage.yml intake-triage
    remote_call pr-review-hosted.yml pr-review
    remote_call pr-review-security-hosted.yml pr-review-security
  ) || return 1
  cat >"$dir/$WF/lane.yml" <<'EOF'
on: workflow_dispatch
jobs:
  run:
    environment:
      name: claude-lanes
      deployment: false
    runs-on: ubuntu-24.04
    steps:
      - run: echo hi
        env:
          KEY: ${{ secrets.ISSUE_LANE_CLAUDE_API_KEY }}
EOF
}

run_case() { test_harness::check_case mk_tree check-claude-secrets-environment.sh "$@"; }

job() {
  {
    printf 'on: %s\njobs:\n  j:\n' "$2"
    [[ -n "$3" ]] && printf '    environment: %s\n' "$3"
    # shellcheck disable=SC2016  # a literal workflow expression, never expanded
    printf '    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n        env:\n          V: ${{ %s }}\n' "$4"
  } >"$WF/$1"
}

NO_ENV="job j reads a Claude secret without environment claude-lanes"
HEAD_REF="names environment claude-lanes in a run started by"

run_case "a lane reading a Claude secret in claude-lanes on a dispatch passes" 0 ":" \
  "(4 job(s), 3 pending ci-workflows call(s))"

run_case "an API key read with no environment fails" 1 \
  "job a.yml workflow_dispatch '' secrets.INTAKE_CLAUDE_API_KEY" \
  "$WF/a.yml:3: $NO_ENV"

run_case "an OAuth token read with no environment fails" 1 \
  "job a.yml schedule '' secrets.SOME_OAUTH_TOKEN" \
  "$WF/a.yml:3: $NO_ENV"

run_case "a lower-case hyphenated Claude secret name fails" 1 \
  "job a.yml workflow_call '' secrets.claude-api-key" \
  "$WF/a.yml:3: $NO_ENV"

run_case "a secret read only in an if expression fails" 1 \
  "job a.yml workflow_dispatch '' \"secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != ''\"" \
  "$WF/a.yml:3: $NO_ENV"

run_case "toJSON(secrets) with no environment fails" 1 \
  "job a.yml workflow_dispatch '' 'toJSON(secrets)'" \
  "$WF/a.yml:3: $NO_ENV"

run_case "a computed secret name with no environment fails" 1 \
  "job a.yml workflow_dispatch '' \"secrets[format('{0}_KEY', 'X')]\"" \
  "$WF/a.yml:3: $NO_ENV"

run_case "a workflow-level env reading a Claude secret fails each job" 1 \
  "printf 'on: workflow_dispatch\nenv:\n  K: \${{ secrets.MAINTENANCE_CLAUDE_API_KEY }}\njobs:\n  j:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n' >$WF/a.yml" \
  "$WF/a.yml:5: $NO_ENV"

run_case "a non-Claude secret with no environment passes" 0 \
  "job a.yml workflow_dispatch '' secrets.DEPLOY_TOKEN"

run_case "the environment by bare name passes" 0 \
  "job a.yml workflow_dispatch claude-lanes secrets.INTAKE_CLAUDE_API_KEY"

run_case "another environment fails" 1 \
  "job a.yml workflow_dispatch pr-pipeline-scan-carrier secrets.INTAKE_CLAUDE_API_KEY" \
  "$WF/a.yml:3: $NO_ENV"

run_case "an environment named by expression fails" 1 \
  "job a.yml workflow_dispatch \"'\\\${{ inputs.env }}'\" secrets.INTAKE_CLAUDE_API_KEY" \
  "$WF/a.yml:3: $NO_ENV"

run_case "claude-lanes on a pull_request workflow fails" 1 \
  "job a.yml pull_request claude-lanes secrets.REVIEWS_CLAUDE_API_KEY" \
  "$WF/a.yml:3: job j $HEAD_REF pull_request,"

run_case "claude-lanes on a pull_request_review_comment workflow fails" 1 \
  "job a.yml pull_request_review_comment claude-lanes secrets.REVIEWS_CLAUDE_API_KEY" \
  "$WF/a.yml:3: job j $HEAD_REF pull_request_review_comment,"

run_case "claude-lanes on a merge_group workflow fails" 1 \
  "job a.yml merge_group claude-lanes secrets.REVIEWS_CLAUDE_API_KEY" \
  "$WF/a.yml:3: job j $HEAD_REF merge_group,"

run_case "claude-lanes on pull_request_target passes" 0 \
  "job a.yml pull_request_target claude-lanes secrets.REVIEWS_CLAUDE_API_KEY"

run_case "claude-lanes on a push to main passes" 0 \
  "job a.yml '{push: {branches: [main]}}' claude-lanes secrets.AUTOMATIONS_CLAUDE_API_KEY"

run_case "claude-lanes on a push to main and another branch fails" 1 \
  "job a.yml '{push: {branches: [main, dev]}}' claude-lanes secrets.AUTOMATIONS_CLAUDE_API_KEY" \
  "$WF/a.yml:3: job j $HEAD_REF push to a branch other than main"

run_case "claude-lanes on an unfiltered push fails" 1 \
  "job a.yml push claude-lanes secrets.AUTOMATIONS_CLAUDE_API_KEY" \
  "$WF/a.yml:3: job j $HEAD_REF push to a branch other than main"

run_case "claude-lanes on a push to main that also takes tags fails" 1 \
  "job a.yml '{push: {branches: [main], tags: [v*]}}' claude-lanes secrets.AUTOMATIONS_CLAUDE_API_KEY" \
  "$WF/a.yml:3: job j $HEAD_REF push to a branch other than main"

run_case "a reusable workflow takes its local caller's pull_request trigger" 1 \
  "job callee.yml workflow_call claude-lanes secrets.claude-api-key &&
   printf 'on: pull_request\njobs:\n  call:\n    uses: ./$WF/callee.yml\n    secrets:\n      claude-api-key: \${{ secrets.PR_UNBLOCK_CLAUDE_API_KEY }}\n' >$WF/caller.yml" \
  "$WF/callee.yml:3: job j $HEAD_REF pull_request"

run_case "a secret a local caller passes under a plain name counts as Claude" 1 \
  "job callee.yml workflow_call '' secrets.TOKEN &&
   printf 'on: workflow_dispatch\njobs:\n  call:\n    uses: ./$WF/callee.yml\n    secrets:\n      TOKEN: \${{ secrets.PR_UNBLOCK_CLAUDE_API_KEY }}\n' >$WF/caller.yml" \
  "$WF/callee.yml:3: $NO_ENV"

run_case "a local call whose callee job names claude-lanes passes" 0 \
  "job callee.yml workflow_call claude-lanes secrets.TOKEN &&
   printf 'on: workflow_dispatch\njobs:\n  call:\n    uses: ./$WF/callee.yml\n    secrets:\n      TOKEN: \${{ secrets.PR_UNBLOCK_CLAUDE_API_KEY }}\n' >$WF/caller.yml"

run_case "a Claude secret passed to another repository's reusable fails" 1 \
  "remote_call other.yml review" \
  "$WF/other.yml:3: job review passes a Claude secret to melodic-software/ci-workflows/.github/workflows/x.yml@main, a reusable workflow outside this repository"

run_case "a remote call passing with: environment: claude-lanes on a dispatch passes" 0 \
  "remote_call other.yml review workflow_dispatch claude-lanes"

run_case "a remote call passing with: environment: claude-lanes on pull_request fails" 1 \
  "remote_call other.yml review pull_request claude-lanes" \
  "$WF/other.yml:3: job review $HEAD_REF pull_request"

run_case "a remote call passing another environment fails" 1 \
  "remote_call other.yml review workflow_dispatch pr-pipeline-scan-carrier" \
  "$WF/other.yml:3: job review passes a Claude secret to melodic-software/ci-workflows/.github/workflows/x.yml@main, a reusable workflow outside this repository"

run_case "a remote call passing the environment by expression fails" 1 \
  "remote_call other.yml review workflow_dispatch \"'\\\${{ inputs.env }}'\"" \
  "$WF/other.yml:3: job review passes a Claude secret to melodic-software/ci-workflows/.github/workflows/x.yml@main, a reusable workflow outside this repository"

run_case "a pending caller that passes with: environment fails as stale" 1 \
  "remote_call pr-review-hosted.yml pr-review workflow_dispatch claude-lanes" \
  "$WF/pr-review-hosted.yml: job pr-review: PENDING_REMOTE in scripts/check-claude-secrets-environment.mjs names it, but it no longer passes a Claude secret"

run_case "secrets: inherit to another repository's reusable fails" 1 \
  "printf 'on: workflow_dispatch\njobs:\n  call:\n    uses: octo/x/.github/workflows/y.yml@main\n    secrets: inherit\n' >$WF/other.yml" \
  "$WF/other.yml:3: job call passes a Claude secret to octo/x/.github/workflows/y.yml@main"

run_case "a pending entry whose call no longer passes a Claude secret fails" 1 \
  "printf 'on: workflow_dispatch\njobs:\n  pr-review:\n    uses: melodic-software/ci-workflows/.github/workflows/x.yml@main\n' >$WF/pr-review-hosted.yml" \
  "$WF/pr-review-hosted.yml: job pr-review: PENDING_REMOTE in scripts/check-claude-secrets-environment.mjs names it, but it no longer passes a Claude secret"

run_case "a workflow that does not parse fails" 1 \
  "printf 'on: [\n' >$WF/broken.yml" \
  "$WF/broken.yml: does not parse as YAML"

tree=""
if mk_tree tree; then
  (cd "$tree" && job a.yml workflow_dispatch '' secrets.INTAKE_CLAUDE_API_KEY)
  test_harness::assert_discover_quiet "$tree/scripts/check-claude-secrets-environment.sh"
else
  fail "discover mode: fixture build failed"
fi

test_harness::assert_unknown_mode "$SUT_SRC"

test_harness::report
