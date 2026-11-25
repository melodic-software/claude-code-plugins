#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/adr skills/release

cat >docs/adr/0001-publish-plugins-through-one-marketplace.md <<'MD'
# 1. Publish plugins through one marketplace

Status: accepted

Consumers install every plugin from one marketplace manifest, so its name is part of each install
command.

## Considered options

- One marketplace per plugin: every consumer would have to register each one.
MD

cat >skills/release/SKILL.md <<'MD'
---
description: Release checklist for a plugin version.
---

1. Run lint.
2. Run the test suite.
3. Bump the version and tag the release.
MD

git add -A
git commit -q -m "Plugin repository with a release skill"
