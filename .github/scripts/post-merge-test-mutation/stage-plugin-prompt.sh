#!/usr/bin/env bash
# stage-plugin-prompt.sh <generate|triage>: the post-merge mutation lane's
# "Stage the plugin and the prompt" step, shared by the three legs of each
# stage. Run with bash from the workspace root, with HEAD_SHA, DIFF_TARGET,
# PROMPT_FILE, SCHEMA_FILE and MODEL from the step env. It stages a read-only
# copy of main's mutation-testing plugin under .lane, the one tree
# run-claude-cli's file tools reach, writes the stage's prompt and schema
# files, and writes lint to GITHUB_OUTPUT. Any other argument exits 2.
# errexit and pipefail match the step shell it replaces (the workflow's
# `shell: bash`).
# shellcheck disable=SC2154 # the step env sets the files, HEAD_SHA, DIFF_TARGET and MODEL, and the runner GITHUB_*
set -eo pipefail

case "${1:-}" in
  generate | triage) stage=$1 ;;
  *)
    echo "usage: stage-plugin-prompt.sh <generate|triage>" >&2
    exit 2
    ;;
esac

[[ -n "$MODEL" ]] || {
  echo "::error::the verify-pr route's model is default, which run-claude-cli cannot pass"
  exit 1
}
mkdir -p .lane/plugins
cp -R .base/plugins/mutation-testing .lane/plugins/
[[ -z "$(find .lane -type l -print -quit)" ]] || {
  echo "::error::the staged plugin holds a symbolic link"
  exit 1
}
chmod -R a-w .lane/plugins
prompt=$(<".base/.github/scripts/post-merge-test-mutation/$stage.prompt.md")
prompt=${prompt//HEAD_SHA/$HEAD_SHA}
prompt=${prompt//DIFF_TARGET/$DIFF_TARGET}
prompt=${prompt//EXECUTED_FILE/mutation-data/executed.json}
printf '%s\n' "$prompt" >"$PROMPT_FILE"
# The model gets the shape without pattern, minimum and maximum, which
# no live lane schema has used with --json-schema; the next job
# checks the whole file.
jq -c 'walk(if type == "object" then del(.pattern, .minimum, .maximum) else . end)' \
  ".base/.github/scripts/post-merge-test-mutation/$stage.schema.json" >"$SCHEMA_FILE"
echo "lint=$GITHUB_WORKSPACE/.lane/plugins/mutation-testing/scripts/suppression-lint.sh" >>"$GITHUB_OUTPUT"
