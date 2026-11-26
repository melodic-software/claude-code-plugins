#!/usr/bin/env bash
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
jq -c 'walk(if type == "object" then del(.pattern, .minimum, .maximum) else . end)' \
  ".base/.github/scripts/post-merge-test-mutation/$stage.schema.json" >"$SCHEMA_FILE"
echo "lint=$GITHUB_WORKSPACE/.lane/plugins/mutation-testing/scripts/suppression-lint.sh" >>"$GITHUB_OUTPUT"
