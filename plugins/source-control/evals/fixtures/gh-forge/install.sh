#!/usr/bin/env bash
# Gives a scaffolded repository an offline forge: a bare `origin` holding the base and head branches,
# and a gh stand-in that serves one open draft pull request from them. Run it from a case's
# scaffold.sh in the workspace, after the base and head branches exist:
#   bash install.sh <number> <head-branch> <base-branch> <title>
#
# The bare repository's path ends in eval-fixture/app.git so push-branch.sh, which compares the
# push remote's URL with the PR's head repository, accepts it as eval-fixture/app.
#
# The stand-in lands in <git dir>/eval-forge/bin. A case puts it first on the run's Bash PATH by
# listing its own `gh-forge-path` plugin subdirectory in prompt.md `plugins:`: that plugin's
# SessionStart hook appends an export of the directory to $CLAUDE_ENV_FILE, which the run's shell
# applies whether it is bash or zsh. A case cannot set PATH (env keys are EVAL_* only), a plugin's
# bin/ is not put on an eval run's PATH, and a plugin a case ships must sit in a subdirectory of
# the case directory, so each case carries its own copy of that one-file plugin.
# Pointers: https://code.claude.com/docs/en/plugin-evals#case-yaml-fields and
# https://code.claude.com/docs/en/hooks#persist-environment-variables, as of 2026-10-13 (Claude
# Code 2.1.296, confirmed by a probe run). Recheck trigger: a Claude Code release that changes
# CLAUDE_ENV_FILE, plugin hooks or bin/ in eval runs, or adds a case-level PATH setting.
set -euo pipefail

number="$1" head="$2" base="$3" title="$4"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
forge="$(git rev-parse --absolute-git-dir)/eval-forge"

mkdir -p "$forge/bin"
cp "$here/gh" "$forge/bin/gh"
chmod +x "$forge/bin/gh"
printf 'PR_NUMBER=%q\nPR_HEAD=%q\nPR_BASE=%q\nPR_TITLE=%q\n' "$number" "$head" "$base" "$title" >"$forge/state"
echo true >"$forge/draft"

git init -q --bare "$forge/eval-fixture/app.git"
git remote add origin "$forge/eval-fixture/app.git"
git push -q origin "$base" "$head"
git branch -q --set-upstream-to="origin/$head" "$head"
