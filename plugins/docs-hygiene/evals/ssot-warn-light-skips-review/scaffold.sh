#!/usr/bin/env bash
# Three docs restate the commit-subject rule in different words; the working notes hold a
# verify result of WARN-borderline and a plan. The default branch sets verification: light.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions docs/guides .work/extract-ssot
printf 'verification: light\n' >docs/conventions/docs-hygiene.yaml
cat >docs/guides/contributing.md <<'MD'
# Contributing

Commit subjects follow Conventional Commits: a type, an optional scope, a colon and a subject.
MD
cat >docs/guides/release.md <<'MD'
# Releasing

Every commit subject must start with a Conventional Commits type such as feat or fix, then a colon.
MD
cat >docs/guides/review.md <<'MD'
# Review

Reviewers reject a commit whose subject is not in Conventional Commits form (type, colon, subject).
MD
printf '.work/\n' >.gitignore
git add -A
git commit -q -m "docs: guides"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git remote set-head origin main
git checkout -q -b docs/commit-subject-ssot
cat >.work/extract-ssot/notes.md <<'MD'
# extract-ssot working notes

## Cluster: commit-subject-rule

- verify: status WARN-borderline, bucket N>=3 (3 instances, semantic; stability test passes,
  reader-burden test does not)
- plan: consolidate into docs/guides/contributing.md "Commit subjects" section (the existing home);
  trim release.md and review.md to a one-line citation of that heading. No new artifact.
- status: plan done, execute next
MD
