#!/usr/bin/env bash
# skill-x, whose SKILL.md line 42 is an illustrative link to a file that is not meant to exist.
set -euo pipefail
d=.claude/skills/skill-x
mkdir -p "$d"
{
  printf -- '---\nname: skill-x\ndescription: "Writes a project overview page. Use when: '\''write the overview'\''."\n---\n\n'
  printf '## Steps\n\n'
  for i in $(seq 1 31); do
    printf '%s. Draft section %s of the overview.\n' "$i" "$i"
  done
  printf '\n## Linking spokes (example only)\n\n'
  printf 'The orchard sample shows the shape of a spoke link, [the big picture](reference/big-picture.md); it is an illustration, and no such file ships with this skill.\n'
} >"$d/SKILL.md"
