#!/usr/bin/env bash
# Seeds a committed legacy testing-format feature map at .claude/skills/feature-map, then leaves an
# uncommitted edit in one of its tracked files, so a refresh must refuse to convert it.
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
printf '%s\n' '- Pausing a timer is not mapped yet; draft note, not committed.' >>"$map/start-a-timer.md"
