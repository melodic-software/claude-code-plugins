#!/usr/bin/env bash
# Gives a scaffolded repository an offline forge: a bare `origin` holding the base and head branches,
# and a gh stand-in that serves one open draft pull request from them. Run it from a case's
# scaffold.sh in the workspace, after the base and head branches exist:
#   bash install.sh <number> <head-branch> <base-branch> <title> [--open] [--failing-check <name>]
# The pull request is a draft unless --open is given. --failing-check adds one failing check with
# that name, which `pr checks` and the pull request's status rollup then report.
#
# origin's URL is https://github.com/eval-fixture/app.git, so push-branch.sh, which compares the
# push remote's URL with the PR's head repository, accepts it as eval-fixture/app on github.com.
# `remote.origin.vcs=evalforge` hands every fetch and push of origin to the git-remote-evalforge
# helper (copied into the stand-in's bin/, which the run's PATH carries), which serves them from the
# local bare repository, so nothing reaches github.com. Without the helper on PATH git fails with
# "remote-evalforge is not a git command" and never falls back to https.
#
# The stand-in lands in <git common dir>/eval-forge/bin. A case puts it first on the run's Bash PATH by
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
shift 4
draft=true failing=""
while (($#)); do
  case "$1" in
    --open) draft=false ;;
    --failing-check)
      failing="${2:?--failing-check needs a check name}"
      shift
      ;;
    *)
      echo "install.sh: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
forge="$(git rev-parse --path-format=absolute --git-common-dir)/eval-forge"
# Added first, so a repository that already has an origin stops here before anything is written.
git remote add origin "https://github.com/eval-fixture/app.git"
git config remote.origin.vcs evalforge

mkdir -p "$forge/bin"
cp "$here/gh" "$forge/bin/gh"
chmod +x "$forge/bin/gh"
cp "$here/git-remote-evalforge" "$forge/bin/git-remote-evalforge"
chmod +x "$forge/bin/git-remote-evalforge"
printf 'PR_NUMBER=%q\nPR_HEAD=%q\nPR_BASE=%q\nPR_TITLE=%q\n' "$number" "$head" "$base" "$title" >"$forge/state"
echo "$draft" >"$forge/draft"
if [[ -n "$failing" ]]; then
  jq -n --arg name "$failing" --arg url "https://github.com/eval-fixture/app/actions/runs/1" \
    '[{name: $name, state: "FAILURE", bucket: "fail", workflow: "ci", link: $url}]' >"$forge/checks"
else
  echo '[]' >"$forge/checks"
fi

git init -q --bare "$forge/eval-fixture/app.git"
export PATH="$forge/bin:$PATH"
git push -q origin "$base" "$head"
git branch -q --set-upstream-to="origin/$head" "$head"
