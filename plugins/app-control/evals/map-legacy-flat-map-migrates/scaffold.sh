#!/usr/bin/env bash
# Seeds a legacy testing-format feature map at .claude/skills/feature-map and no control skill.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
map=.claude/skills/feature-map
mkdir -p "$map" apps/web/src
cp "$here/fixtures/index.md" "$map/SKILL.md"
cp "$here/fixtures/start-a-timer.md" "$map/start-a-timer.md"
: >apps/web/src/TimerRow.tsx
