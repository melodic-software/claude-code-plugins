#!/usr/bin/env bash
# Seed a repo whose review skill moved to code-review, leaving stale references in several forms.
set -euo pipefail

mkdir -p .claude/skills/plan .claude/skills/code-review .claude/skills/ship .claude/rules .claude/agents docs
cat >.claude/skills/plan/SKILL.md <<'MD'
---
name: plan
description: Write the implementation plan before any code changes.
---

# Plan

List the files to change and the checks that prove the change works.
MD
cat >.claude/skills/code-review/SKILL.md <<'MD'
---
name: code-review
description: Check the finished diff for correctness bugs before it merges.
---

# Code review

Read the diff, run the tests, and report each bug with its file and line.
MD
cat >.claude/skills/ship/SKILL.md <<'MD'
---
name: ship
description: Tag and publish the release once the diff is approved.
---

# Ship

Bump the version, tag it, and publish.
MD
cat >.claude/rules/stages.md <<'MD'
---
paths:
  - ".claude/skills/{plan,review,ship}/**"
---

# Stage skills

Every stage skill ends by naming the next stage and the command that starts it.
MD
cat >.claude/agents/shipper.md <<'MD'
---
name: shipper
description: "Final stage of plan → review → ship: tags and publishes the release."
tools: Read, Bash
---

Publish only from `main`.
MD
cat >docs/workflow.md <<'MD'
# Workflow

Every change goes through three skills in order.

| Step | When |
|---|---|
| 1. plan | before writing code |
| 2. review | once the diff is ready |
| 3. ship | after approval |

Ask a teammate to review anything that touches billing.
MD
cat >docs/architecture.md <<'MD'
# Architecture

Each stage is a skill: [plan](../.claude/skills/plan/SKILL.md),
[review](../.claude/skills/review/SKILL.md) and [ship](../.claude/skills/ship/SKILL.md).
MD
cat >README.md <<'MD'
# Acme tools

Run `/plan`, then `/review`, then `/ship`.

Maintainers review every pull request within two days.
MD
cat >CHANGELOG.md <<'MD'
# Changelog

## 1.4.0 - 2026-09-02

- Added the `/review` skill for pre-merge checks.

## 1.3.0 - 2026-08-11

- Added the `/plan` skill.
MD
