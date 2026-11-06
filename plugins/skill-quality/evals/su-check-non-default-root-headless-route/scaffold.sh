#!/usr/bin/env bash
# Two skills under a non-default root, packages/agent/skills; no .claude/skills.
set -euo pipefail
for s in tidy-imports release-notes; do
  mkdir -p "packages/agent/skills/$s"
  printf -- '---\nname: %s\ndescription: "Fixture skill %s. Use when: testing."\n---\n\nFixture body.\n' "$s" "$s" >"packages/agent/skills/$s/SKILL.md"
done
