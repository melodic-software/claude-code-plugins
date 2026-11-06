#!/usr/bin/env bash
# One skill that ships no evals/evals.json.
set -euo pipefail
mkdir -p .claude/skills/my-skill
printf -- '---\nname: my-skill\ndescription: "Formats release notes from merged pull requests. Use when: '\''write release notes'\''."\n---\n\n## Steps\n\n1. Draft the notes.\n' >.claude/skills/my-skill/SKILL.md
