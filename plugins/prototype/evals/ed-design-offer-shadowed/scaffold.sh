#!/usr/bin/env bash
# Seeds a project skill named design, so the session's skill listing holds a local design skill.
set -euo pipefail
mkdir -p .claude/skills/design
cat >.claude/skills/design/SKILL.md <<'EOF'
---
name: design
description: "Team notes on our brand colors and spacing scale. Use when asked about our brand palette."
---

Our brand palette is navy and sand; the spacing scale is 4, 8, 16, 32.
EOF
