#!/usr/bin/env bash
# Seeds a committed control skill on main plus a testing-era upkeep branch,
# feature-map-upkeep/claude-skills-feature-map, local and remote, so a refresh must find and report it.
set -euo pipefail

# Init a repository here unless this directory already is one's top level, so the commit never lands
# in an enclosing repository.
if [[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" != "$(pwd -P)" ]]; then
  git init -q -b main
fi
git config user.name eval
git config user.email eval@example.invalid
skill=.claude/skills/control-clockwork
mkdir -p "$skill/features/weekly-timesheet-export" src
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

- weekly timesheet export | features/weekly-timesheet-export/README.md | entry points: 1 | sources: src/routes.ts
MD
cat >"$skill/features/weekly-timesheet-export/README.md" <<'MD'
# Weekly timesheet export

## Parts

- export: a CSV with one row per time entry for the chosen week

## Sub-features

none

## Entry points

- the `/reports/timesheet` page: driven

## Reset

Seed the scratch database with one week of entries.

## Drive

- Open the `/reports/timesheet` page and choose `Export`.

## Gotchas

none
MD
: >src/routes.ts
git add -A
git commit -q -m "Clockwork web with its control skill"
# The testing-era upkeep branch, with its own commit, local and as a remote-tracking ref.
git switch -q -c feature-map-upkeep/claude-skills-feature-map
: >src/.feature-map-upkeep
git add src/.feature-map-upkeep
git commit -q -m "Refresh the feature map"
git switch -q main
git update-ref refs/remotes/origin/feature-map-upkeep/claude-skills-feature-map feature-map-upkeep/claude-skills-feature-map
# Keep the loose refs and also list every ref in .git/packed-refs, one readable file.
git pack-refs --all --no-prune
