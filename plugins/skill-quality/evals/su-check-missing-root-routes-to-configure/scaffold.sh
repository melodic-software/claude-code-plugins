#!/usr/bin/env bash
# A workspace with no .claude/skills directory and no SKILL.md anywhere.
set -euo pipefail
mkdir -p docs
printf '# Notes\n\nNothing here is a skill.\n' >docs/notes.md
