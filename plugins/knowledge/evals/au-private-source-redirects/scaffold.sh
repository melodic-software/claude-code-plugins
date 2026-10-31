#!/usr/bin/env bash
# This repository has a github.com remote that gh cannot read in the sandbox,
# so docs/upstream reads `unknown` (handled as public). The source is a local
# checkout at upstream-src/acme-internal-skills with one commit and a
# github.com remote for acme/internal-skills, so it reads `unknown` (handled
# as private). The checkout sits inside the working directory, with its own
# git init, because a sibling of the working directory may not reach the run.
set -euo pipefail

git init -q
git remote add origin https://github.com/acme/open-tools.git

src=upstream-src/acme-internal-skills
mkdir -p "$src/skills/release-notes"
printf '# release-notes\n\nDrafts release notes from merged pull requests.\n' \
  >"$src/skills/release-notes/SKILL.md"
git -C "$src" init -q
git -C "$src" add -A
git -C "$src" -c user.name=Eval -c user.email=eval@example.com -c commit.gpgsign=false \
  commit -q -m "Add release-notes skill"
git -C "$src" remote add origin https://github.com/acme/internal-skills.git
printf 'upstream-src/\n' >>.git/info/exclude
