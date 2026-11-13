#!/usr/bin/env bash
# prepare-working-tree.sh: the tidy lane's "Prepare the working tree" step,
# shared by its three model legs. Sets the commit identity, keeps .lane/ out
# of git, takes the head's instruction, settings and server files out of the
# session (skip-worktree keeps their removal out of every commit) and stages a
# read-only copy of the plugins from STAGE. Run with bash from the workspace
# root, with MODEL and STAGE from the step env. errexit and pipefail match the
# step shell it replaces (the workflow's `shell: bash`).
# shellcheck disable=SC2154 # the step env sets MODEL and STAGE
set -eo pipefail

[[ -n "$MODEL" ]] || {
  echo "::error::the resolve-issue route's model is default, which run-claude-cli cannot pass"
  exit 1
}
git config user.name "maintenance-tidy-code-upkeep"
git config user.email "maintenance-tidy-code-upkeep@users.noreply.github.com"
printf '.lane/\n' >>.git/info/exclude
# Head instruction, settings and server files stay out of the session;
# skip-worktree keeps their removal out of every commit.
mapfile -t held < <(git ls-files -- ':(glob)**/CLAUDE.md' ':(glob)**/AGENTS.md' ':(glob)**/.mcp.json' ':(glob)**/.claude/**' CLAUDE.md AGENTS.md .mcp.json)
if ((${#held[@]})); then
  git update-index --skip-worktree -- "${held[@]}"
  rm -f -- "${held[@]}"
fi
mkdir .lane
cp -R "$STAGE/plugins" .lane/plugins
chmod -R a-w .lane/plugins
