#!/usr/bin/env bash
# Seeds two committed control skills, control-admin and control-shop, on main, so a bare unattended
# refresh must take each in turn on its own upkeep branch.
set -euo pipefail

# Init a repository here unless this directory already is one's top level, so the commit never lands
# in an enclosing repository.
if [[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" != "$(pwd -P)" ]]; then
  git init -q -b main
fi
git config user.name eval
git config user.email eval@example.invalid

# seed <slug> <app> <feature> <entry point>
seed() {
  local skill=".claude/skills/control-$1"
  mkdir -p "$skill/features/$3" "$1"
  cat >"$skill/SKILL.md" <<MD
---
description: "Launch, ready-check, capture and clean up the $2 app."
---

- App: $2, built from \`$1/\`
- Driving tool: playwright

## Launch

Run the \`run-$1\` skill.

## Ready

\`curl -fsS http://127.0.0.1:8080/healthz\`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- $3 | features/$3/README.md | entry points: 1 | sources: $1/$3.py
MD
  cat >"$skill/features/$3/README.md" <<MD
# $3

## Parts

- $3

## Sub-features

none

## Entry points

- $4: driven

## Reset

Seed the scratch database.

## Drive

- Use $4.

## Gotchas

none
MD
  : >"$1/$3.py"
}
# shellcheck disable=SC2016 # the backticks are literal markdown, not command substitution
seed admin "Admin console" users 'the `/admin/people` page'
# shellcheck disable=SC2016 # the backticks are literal markdown, not command substitution
seed shop Shop cart 'the `Add to basket` button'
git add -A
git commit -q -m "Admin console and shop with their control skills"
# Name the starting branch main whatever branch an existing repository started on.
git branch -M main
