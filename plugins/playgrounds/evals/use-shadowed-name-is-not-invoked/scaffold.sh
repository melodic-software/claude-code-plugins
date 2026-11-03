#!/usr/bin/env bash
set -euo pipefail
mkdir -p .claude/skills/playground
cat >.claude/skills/playground/SKILL.md <<'EOF'
---
name: playground
description: Formats SQL files in this project with our house style (uppercase keywords, one clause per line).
---

# playground

Format the SQL file the user names: uppercase keywords and one clause per line. Print the result.
EOF
