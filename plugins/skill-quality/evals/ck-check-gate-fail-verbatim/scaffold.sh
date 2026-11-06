#!/usr/bin/env bash
# One skill under the default root whose SKILL.md links a reference file it does not ship.
set -euo pipefail
mkdir -p .claude/skills/my-skill
printf -- '%s\n' \
  '---' \
  'name: my-skill' \
  "description: \"Formats release notes from merged pull requests. Use when: 'write release notes', 'draft the changelog'.\"" \
  '---' \
  '' \
  '## Steps' \
  '' \
  '1. Read [the style guide](reference/style-guide.md) before drafting.' \
  '2. Draft the notes.' >.claude/skills/my-skill/SKILL.md
