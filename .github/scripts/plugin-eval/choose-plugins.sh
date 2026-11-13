#!/usr/bin/env bash
# Chooses the plugins an eval leg runs: the target input on a dispatch, else
# the pull request head's diff through select-plugins.mjs. Reads EVENT, TARGET,
# BASE_SHA and HEAD_SHA; writes go and list to GITHUB_OUTPUT.
# shellcheck disable=SC2153,SC2154,SC2292 # the step's body verbatim; the step env sets EVENT, TARGET, BASE_SHA and HEAD_SHA, and the runner GITHUB_OUTPUT
set -e
if [ "$EVENT" = workflow_dispatch ]; then
  target=${TARGET%/}
  if ! [[ $target =~ ^plugins/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "::error::target must be a plugin directory, plugins/<name>"
    exit 1
  fi
  selected=$target
else
  merge_base=$(git -C .head merge-base "$BASE_SHA" "$HEAD_SHA")
  files=$(git -C .head diff --no-renames --name-only "$merge_base" "$HEAD_SHA")
  selected=$(printf '%s\n' "$files" |
    node .base/.github/scripts/plugin-eval/select-plugins.mjs --repo .head --base "$merge_base" --head "$HEAD_SHA") || {
    echo "::error::the pull request changes more of a selected plugin than its suite may run with the credential"
    exit 1
  }
fi
if [ -z "$selected" ]; then
  echo "::notice::the pull request changes no plugin's skills, agents or evals; no eval runs."
  echo "go=false" >>"$GITHUB_OUTPUT"
  exit 0
fi
{
  echo "go=true"
  echo "list<<EOF"
  echo "$selected"
  echo "EOF"
} >>"$GITHUB_OUTPUT"
