#!/usr/bin/env bash
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-$ROOT/.github/workflows/pr-require-checks.yml}"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

job_of() {
  awk -v job="  $1:" '$0 == job { on = 1; print; next } on && /^  [A-Za-z0-9_-]+:$/ { exit } on { print }' "$WORKFLOW"
}

permissions_of() {
  awk '/^    permissions:$/ { on = 1; next } on && /^      [a-z-]+: [a-z]+$/ { sub(/^ +/, ""); print; next } on { exit }' <<<"$1"
}

mark_lanes="$(job_of mark-lanes)"
if [[ -z "$mark_lanes" ]]; then
  fail "the workflow has no mark-lanes job"
elif grep -qE '^ +(- )?uses: ' <<<"$mark_lanes"; then
  fail "mark-lanes, which holds statuses: write, checks out or runs an action"
else
  ok "mark-lanes runs no checkout and no action, so no pull request code runs beside its write token"
fi
if [[ "$(permissions_of "$mark_lanes")" == "statuses: write" ]]; then
  ok "mark-lanes holds statuses: write and nothing else"
else
  fail "mark-lanes permissions are not exactly statuses: write: $(permissions_of "$mark_lanes" | paste -sd, -)"
fi
# shellcheck disable=SC2016 # workflow expression to match, not shell
if grep -qxF "        if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.id == github.repository_id" <<<"$mark_lanes"; then
  ok "mark-lanes writes the in-flight status only for a same-repository head, matched by id"
else
  fail "mark-lanes' status write lost its same-repository-by-id condition"
fi

ci_status="$(job_of ci-status)"
# shellcheck disable=SC2016 # workflow expression to match, not shell
if grep -qxF '    if: ${{ !cancelled() }}' <<<"$ci_status"; then
  ok "ci-status runs whenever the run is not cancelled, so a failed or skipped lane reaches the aggregate"
else
  fail "ci-status lost its job-level if: \${{ !cancelled() }}"
fi

managed="$(job_of check-managed-files)"
if [[ "$(permissions_of "$managed" | paste -sd, -)" == "contents: read,pull-requests: read" ]]; then
  ok "check-managed-files holds read-only contents and pull-requests"
else
  fail "check-managed-files permissions changed: $(permissions_of "$managed" | paste -sd, -)"
fi

missing="$(awk '
  /^ +(- )?uses: actions\/checkout@/ { if (open) print at; open = 1; at = NR; indent = match($0, /[^ -]/); next }
  open && /persist-credentials: false$/ { open = 0; next }
  open && /^ *- / && match($0, /[^ -]/) <= indent { print at; open = 0 }
  END { if (open) print at }
' "$WORKFLOW" | paste -sd, -)"
total="$(grep -cE '^ +(- )?uses: actions/checkout@' "$WORKFLOW")"
if ((total == 0)); then
  fail "the workflow has no actions/checkout step"
elif [[ -z "$missing" ]]; then
  ok "all $total actions/checkout steps set persist-credentials: false, so no later step inherits the job token in .git/config"
else
  fail "actions/checkout without persist-credentials: false at line(s) $missing"
fi

# shellcheck disable=SC2016 # jq program to match, not shell
if grep -qF "head_ref=\"\$(jq -r --arg repo \"\$GITHUB_REPOSITORY\" 'if .head.repo.full_name == \$repo then .head.ref else \"\" end' <<<\"\$pr\")\"" "$WORKFLOW"; then
  ok "a queued pull request's head branch counts only from this repository, never a fork's same-named branch"
else
  fail "the queued pull request's head_ref read lost its same-repository filter"
fi

test_harness::report
