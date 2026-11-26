#!/usr/bin/env bash
# shellcheck disable=SC2154 # the step env sets MODEL and STAGE
set -eo pipefail

[[ -n "$MODEL" ]] || {
  echo "::error::the resolve-issue route's model is default, which run-claude-cli cannot pass"
  exit 1
}
git config user.name "maintenance-tidy-code-upkeep"
git config user.email "maintenance-tidy-code-upkeep@users.noreply.github.com"
printf '.lane/\n' >>.git/info/exclude
mapfile -t held < <(git ls-files -- ':(glob)**/CLAUDE.md' ':(glob)**/AGENTS.md' ':(glob)**/.mcp.json' ':(glob)**/.claude/**' CLAUDE.md AGENTS.md .mcp.json)
if ((${#held[@]})); then
  git update-index --skip-worktree -- "${held[@]}"
  rm -f -- "${held[@]}"
fi
mkdir .lane
cp -R "$STAGE/plugins" .lane/plugins
chmod -R a-w .lane/plugins
