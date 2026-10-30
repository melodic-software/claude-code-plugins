#!/usr/bin/env bash
# This repository has no remote (reads `local`). The source is a local
# checkout at upstream-src/acme-internal-skills with one commit and a
# github.com remote for acme/internal-skills, so it reads `unknown` (handled
# as private). The absolute --out /srv/repos/acme-corpus/docs/upstream does not
# exist in the sandbox; it is judged by its nearest existing ancestor, which is
# in no git repository, so it reads `local` and head keeps it.
set -euo pipefail

git init -q

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
