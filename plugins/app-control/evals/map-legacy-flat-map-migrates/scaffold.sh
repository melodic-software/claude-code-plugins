#!/usr/bin/env bash
# Seeds a legacy testing-format feature map at .claude/skills/feature-map and no control skill, and
# commits the whole tree on main so the refresh starts from a clean, committed repository.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Init a repository here unless this directory already is one's top level, so the commit never lands
# in an enclosing repository.
if [[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" != "$(pwd -P)" ]]; then
  git init -q -b main
fi
git config user.name eval
git config user.email eval@example.invalid
map=.claude/skills/feature-map
mkdir -p "$map" apps/web/src
cp "$here/fixtures/index.md" "$map/SKILL.md"
cp "$here/fixtures/start-a-timer.md" "$map/start-a-timer.md"
: >apps/web/src/TimerRow.tsx
git add -A
GIT_AUTHOR_DATE=2026-10-01T09:00:00Z GIT_COMMITTER_DATE=2026-10-01T09:00:00Z \
  git commit -q -m "Clockwork web with its feature map"
