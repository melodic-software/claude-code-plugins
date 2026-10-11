#!/usr/bin/env bash
# Gives a scaffolded repository an offline forge: a bare `origin` holding the base and head branches,
# and a gh stand-in that serves one open draft pull request from them. Run it from a case's
# scaffold.sh in the workspace, after the base and head branches exist:
#   bash install.sh <number> <head-branch> <base-branch> <title>
#
# The bare repository's path ends in eval-fixture/app.git so push-branch.sh, which compares the
# push remote's URL with the PR's head repository, accepts it as eval-fixture/app.
#
# A case cannot set PATH, so the stand-in is put on it through the run's temporary home, which is
# the scaffold's HOME (https://code.claude.com/docs/en/plugin-evals#add-setup-or-history-with-case-yaml,
# as of 2026-10-11). Under Claude Code 2.1.296 an eval run does not source ~/.zshrc, ~/.bashrc or
# ~/.profile, but zsh reads ~/.zshenv for every `zsh -c`, so the stand-in is reached only when the
# operator's SHELL is zsh; under bash the run reaches the real gh, which has no login there.
# Recheck trigger: a Claude Code release that changes how an eval run's shell starts.
set -euo pipefail

number="$1" head="$2" base="$3" title="$4"

# Refuse outside an eval run, so a scaffold run by hand never edits the operator's own ~/.zshenv.
# ~user expands from the account database, not from HOME; an unresolved lookup refuses too.
user="$(id -un)"
[[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] && eval "real_home=~$user" || real_home=""
if [[ "$real_home" != /* || "$HOME" -ef "$real_home" ]]; then
  echo "gh-forge/install.sh: HOME is the account's real home, or it could not be checked; run this only from an eval scaffold" >&2
  exit 1
fi
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

# shellcheck disable=SC2016 # $PATH expands when zsh reads the file, not here
printf 'export PATH=%q:"$PATH"\n' "$forge/bin" >>"$HOME/.zshenv"
