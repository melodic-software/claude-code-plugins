#!/usr/bin/env bash
# Seed one short, single-purpose skill with no bundled files.
set -euo pipefail

mkdir -p .claude/skills/changelog-entry

cat >.claude/skills/changelog-entry/SKILL.md <<'MD'
---
name: changelog-entry
description: Write one CHANGELOG.md entry for the change on the current branch. Use when a pull request needs its changelog line.
---

# Changelog entry

Add one entry for the current branch's change to `CHANGELOG.md`.

## Steps

1. Read the branch's commits since it left `main`.
2. Pick the section: `Added` for a new capability, `Changed` for changed behavior, `Fixed` for a
   bug fix, `Removed` for a removed capability.
3. Write one line in the past tense that says what a user notices, not how the code changed.
4. Put it under `## Unreleased`, in the chosen section; create the section if it is missing.
5. Show the diff of `CHANGELOG.md` and stop. The author commits it.

## Rules

- One entry per pull request, even when it has many commits.
- No issue or pull request numbers in the line; the release tooling adds them.
- Leave released sections untouched.

## Examples

- Added: Export of invoices as CSV from the billing page.
- Fixed: Search no longer drops results that contain an apostrophe.
- Changed: Session timeout is now 30 minutes instead of 15.
MD
