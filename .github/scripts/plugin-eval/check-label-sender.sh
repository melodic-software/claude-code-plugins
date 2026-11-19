#!/usr/bin/env bash
# Refuses an untrusted trigger verdict, a draft pull request, or a run no
# `eval: run` label from a listed human started. The recorder run is the head's
# copy, so nothing it wrote is read: the label event comes from the API
# (https://docs.github.com/en/rest/issues/events). Reads PROCEED, REASON, LIST,
# PR_NUMBER, ACTOR_ID, RUN_CREATED_AT and RUN_PATH.
# shellcheck disable=SC2154,SC2292,SC2310 # gh failing in a condition refuses the run; the step env sets PROCEED, REASON, LIST, PR_NUMBER, ACTOR_ID, RUN_CREATED_AT and RUN_PATH
set -eo pipefail
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
if [ "$PROCEED" != true ]; then
  echo "::error::the trigger is not trusted (reason: ${REASON:-unreadable})"
  exit 1
fi
if [ "$RUN_PATH" != .github/workflows/pr-record-eval-label.yml ]; then
  echo "::error::untrusted-actor: the run that started this one is not pr-record-eval-label.yml"
  exit 1
fi
if ! [[ $PR_NUMBER =~ ^[1-9][0-9]*$ && $ACTOR_ID =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::no-pr: the trigger named no pull request or labeling actor"
  exit 1
fi
if ! jq -e --argjson id "$ACTOR_ID" 'any(.actors[]; .id == $id and .kind == "human")' "$LIST" >/dev/null; then
  echo "::error::untrusted-actor: the 'eval: run' label did not come from a listed human"
  exit 1
fi
if [ "$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq '.draft')" != false ]; then
  echo "::error::the pull request is a draft, or its state did not read"
  exit 1
fi
if ! gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/events?per_page=100" --jq '.[]' |
  jq -se --argjson id "$ACTOR_ID" --arg at "$RUN_CREATED_AT" '
    ($at | fromdateiso8601) as $t
    | any(.[]; (.created_at | fromdateiso8601) as $c
        | .event == "labeled" and .label.name == "eval: run" and .actor.id == $id
          and $c <= $t and $c >= $t - 600)' >/dev/null; then
  echo "::error::untrusted-actor: no 'eval: run' label from the triggering actor started this run"
  exit 1
fi
