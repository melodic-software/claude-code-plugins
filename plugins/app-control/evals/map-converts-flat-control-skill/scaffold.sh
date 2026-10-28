#!/usr/bin/env bash
# Seeds a committed control skill whose two feature files are flat features/<id>.md, one of them
# with a ## States section, so a refresh must convert both to folders in its upkeep pull request.
set -euo pipefail

# Init a repository here unless this directory already is one's top level, so the commit never lands
# in an enclosing repository.
if [[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" != "$(pwd -P)" ]]; then
  git init -q -b main
fi
git config user.name eval
git config user.email eval@example.invalid
skill=.claude/skills/control-clockwork
mkdir -p "$skill/features" src
cat >"$skill/SKILL.md" <<'MD'
---
description: "Launch, ready-check, capture and clean up the Clockwork web app."
---

- App: Clockwork web, built from `src/`
- Driving tool: playwright

## Launch

Run the `run-clockwork` skill.

## Ready

`curl -fsS http://127.0.0.1:5180/healthz`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- start a timer | features/start-a-timer.md | entry points: 2 | sources: src/TimerRow.tsx
- approve a timesheet | features/approve-timesheet.md | entry points: 1 | sources: src/Approvals.tsx
MD
cat >"$skill/features/start-a-timer.md" <<'MD'
# Start a timer

## Parts

- start: a new timer begins at 00:00 for the chosen project

## Sub-features

none

## Entry points

- the `Start` button on the dashboard: driven
- pressing `t` anywhere on the dashboard: driven

## States

- The scratch database holds the project `Website refresh` and no running timer.

## Drive

- Choose `Start` in the row named `Website refresh`; the row shows a running clock within two seconds.

## Gotchas

- A timer left running from an earlier run makes `start` look like a switch.
MD
cat >"$skill/features/approve-timesheet.md" <<'MD'
# Approve a timesheet

## Parts

- approve: a manager approves a submitted timesheet

## Sub-features

none

## Entry points

- the `Approve` button on a submitted timesheet: driven

## Reset

Seed the scratch database with one submitted timesheet.

## Drive

- Choose `Approve` on the submitted timesheet; the row shows `Approved`.

## Gotchas

none
MD
: >src/TimerRow.tsx
: >src/Approvals.tsx
git add -A
GIT_AUTHOR_DATE=2026-10-01T09:00:00Z GIT_COMMITTER_DATE=2026-10-01T09:00:00Z \
  git commit -q -m "Clockwork web with its control skill"
