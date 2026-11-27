#!/usr/bin/env bash
# shellcheck disable=SC2154 # the step env sets MODEL, STAGE and BRANCH
set -eo pipefail

[[ -n "${MODEL}" ]] || {
  echo "::error::the resolve-issue route's model is default, which run-claude-cli cannot pass"
  exit 1
}
[[ -n "${BRANCH}" ]] || {
  echo "::error::no default branch name, which the scan's candidate-file path needs"
  exit 1
}
git switch --quiet --force-create "${BRANCH}"
printf '.lane/\n.work/\n' >>.git/info/exclude
listed="$(git ls-files -- ':(glob)**/CLAUDE.md' ':(glob)**/AGENTS.md' ':(glob)**/.mcp.json' ':(glob)**/.claude/**' CLAUDE.md AGENTS.md .mcp.json)"
mapfile -t held <<<"${listed}"
if [[ -n "${listed}" ]]; then
  git update-index --skip-worktree -- "${held[@]}"
  rm -f -- "${held[@]}"
fi
mkdir .lane
cp -R "${STAGE}/plugins" .lane/plugins
mkdir .work
mkdir -p .claude/commands .claude/agents
find . -mindepth 1 \( -path ./.git -o -path ./.work \) -prune -o ! -type l -exec chmod a-w {} +
chmod -R a-w .git/hooks
