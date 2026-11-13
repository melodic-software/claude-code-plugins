#!/usr/bin/env bash
# read-checker-model.sh: the merge-risk legs' "Read the checker's model" step.
# Refuses a default model and a subagent model that is not an alias, then
# writes model and force to GITHUB_OUTPUT. Run with bash from the workspace
# root, with MODEL and SETTINGS from the step env. errexit and pipefail match
# the step shell it replaces (the workflow's `shell: bash`).
# shellcheck disable=SC2154 # the step env sets MODEL and SETTINGS, and the runner GITHUB_OUTPUT
set -eo pipefail

if [[ -z "$MODEL" ]]; then
  echo "::error::the merge-risk profile's model is default, which run-claude-cli cannot pass; name an alias"
  exit 1
fi
model=$(jq -r '.env.CLAUDE_CODE_SUBAGENT_MODEL // ""' <<<"$SETTINGS")
if [[ -n "$model" ]] && ! [[ $model =~ ^(haiku|sonnet|opus)$ ]]; then
  echo "::error::the merge-risk profile's subagent-model is not an alias"
  exit 1
fi
echo "model=$model" >>"$GITHUB_OUTPUT"
echo "force=$([[ -n "$model" ]] && echo 1)" >>"$GITHUB_OUTPUT"
