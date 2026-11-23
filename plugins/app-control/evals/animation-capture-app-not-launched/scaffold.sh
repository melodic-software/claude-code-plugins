#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .claude/skills/control-shop tools
cp "$here/fixtures/control-shop.md" .claude/skills/control-shop/SKILL.md
cp "$here/fixtures/anim-capture.mjs" tools/anim-capture.mjs
