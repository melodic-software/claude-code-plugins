#!/usr/bin/env bash
# One skill whose legacy evals.json has a second case with no prompt.
set -euo pipefail
d=.claude/skills/my-skill
mkdir -p "$d/evals"
printf -- '---\nname: my-skill\ndescription: "Formats release notes from merged pull requests. Use when: '\''write release notes'\''."\n---\n\n## Steps\n\n1. Draft the notes.\n' >"$d/SKILL.md"
cat >"$d/evals/evals.json" <<'EOF'
{
  "skill_name": "my-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "Write release notes for the last three merged pull requests.",
      "expected_output": "Release notes grouped under Added, Changed and Fixed, one line per pull request."
    },
    {
      "id": 2,
      "expected_output": "The notes name each pull request by number."
    }
  ]
}
EOF
