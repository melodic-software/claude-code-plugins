#!/usr/bin/env bash
# Seed a commit-subject rule owned by a conventions doc and recapped inline by three agent-facing files.
set -euo pipefail

mkdir -p docs/conventions .claude/agents .claude/skills/ship prompts
cat >docs/conventions/commits.md <<'MD'
# Commit conventions

## Messages

### Commit subject format

Write the subject in the imperative mood, at most 72 characters, with no trailing period. Start it
with one of the types `feat`, `fix`, `docs` or `chore`, then a colon and a space.

### Commit body

Wrap the body at 100 columns. Say why the change was made; the diff already shows what changed.
MD
cat >.claude/agents/committer.md <<'MD'
---
name: committer
description: Stages the finished change and writes the commit.
tools: Read, Bash
---

Stage only the files the task changed.

When you write the commit, make the subject imperative, 72 characters at most, with no period at
the end, and begin it with feat:, fix:, docs: or chore: and a space.

Never amend a commit that is already pushed.
MD
cat >.claude/skills/ship/SKILL.md <<'MD'
---
name: ship
description: Commit, push and open a pull request for the finished change.
---

# Ship

1. Run the tests.
2. Commit. Subject rules: imperative mood, no more than 72 chars, no trailing period, prefixed
   with `feat:`, `fix:`, `docs:` or `chore:`.
3. Push the branch and open the pull request.
MD
cat >prompts/nightly-release.md <<'MD'
Collect the merged changes since the last tag and bump the version.

Commit the version bump with a subject of at most 72 characters, written in the imperative and
without a full stop at the end, starting with one of feat, fix, docs or chore followed by ": ".

Then tag the release.
MD
cat >CONTRIBUTING.md <<'MD'
# Contributing

Commit messages follow docs/conventions/commits.md.
MD
