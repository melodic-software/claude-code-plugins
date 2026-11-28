#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/adr skills/review skills/report skills/triage findings

cat >docs/adr/0001-publish-plugins-through-one-marketplace.md <<'MD'
# 1. Publish plugins through one marketplace

Status: accepted

Consumers install every plugin from one marketplace manifest, so its name is part of each install
command.

## Considered options

- One marketplace per plugin: every consumer would have to register each one.
MD

cat >skills/review/SKILL.md <<'MD'
---
description: Review a change and write its findings file.
---

Write each finding as one row of the table in `findings/<run>.md`.
MD

cat >skills/report/SKILL.md <<'MD'
---
description: Summarize a run's findings file.
---

Read `findings/<run>.md` and group its rows by severity.
MD

cat >skills/triage/SKILL.md <<'MD'
---
description: Triage a run's findings file.
---

Read `findings/<run>.md` and pick the rows to fix first.
MD

cat >findings/2026-11-01.md <<'MD'
| Severity | File | Finding |
|---|---|---|
| high | src/auth.py:12 | token compared with == |
MD

git add -A
git commit -q -m "Review, report and triage skills sharing a findings file"
