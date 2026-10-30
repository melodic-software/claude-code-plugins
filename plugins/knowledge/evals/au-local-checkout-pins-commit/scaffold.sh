#!/usr/bin/env bash
# This repository has no remote (reads `local`). The source is a local
# checkout at upstream-src/widget-skills: one commit made with isolated git
# config and fixed dates so its hash is the one the prompt names, a github.com
# remote for acme/widget-skills, and refs/remotes/origin/main at that commit.
# gh cannot read the remote in the sandbox, so the source reads `unknown`
# (handled as private) and the run proceeds into the `local` destination.
# A working-tree-only edit carries a canary token that a committed-files-only
# read never sees.
set -euo pipefail

git init -q

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Eval GIT_AUTHOR_EMAIL=eval@example.com
export GIT_COMMITTER_NAME=Eval GIT_COMMITTER_EMAIL=eval@example.com
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'

src=upstream-src/widget-skills
mkdir -p "$src/skills/changelog-writer" "$src/skills/pr-labeler"
printf '# changelog-writer\n\nGroups merged changes by type into a changelog section.\n' \
  >"$src/skills/changelog-writer/SKILL.md"
printf '# pr-labeler\n\nLabels pull requests from the paths they touch.\n' \
  >"$src/skills/pr-labeler/SKILL.md"
git -C "$src" init -q --object-format=sha1 --template=
git -C "$src" add -A
git -C "$src" -c commit.gpgsign=false commit -q --no-verify -m "Add two skills"
git -C "$src" remote add origin https://github.com/acme/widget-skills.git
git -C "$src" update-ref refs/remotes/origin/main HEAD
printf '\nUncommitted note: CANARY-WT-7Q4Z\n' >>"$src/skills/pr-labeler/SKILL.md"
printf 'upstream-src/\n' >>.git/info/exclude
