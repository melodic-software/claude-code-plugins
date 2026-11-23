#!/usr/bin/env bash
set -euo pipefail

mkdir -p my-plugin/.claude-plugin my-plugin/skills/summarize my-plugin/skills/export \
  my-plugin/evals/summarize-standup/graders

cat >my-plugin/.claude-plugin/plugin.json <<'JSON'
{
  "name": "notes",
  "version": "0.1.0",
  "description": "Summarize and export meeting notes"
}
JSON

cat >my-plugin/skills/summarize/SKILL.md <<'MD'
---
description: "Summarize meeting notes into decisions and owners. Use when asked to summarize a meeting or standup."
---

# Summarize meeting notes

List each decision with its owner, then open questions.
MD

cat >my-plugin/skills/export/SKILL.md <<'MD'
---
description: "Export meeting notes to a markdown file. Use when asked to save or export notes."
---

# Export meeting notes

Write the notes to notes/<date>.md.
MD

cat >my-plugin/evals/summarize-standup/prompt.md <<'MD'
---
description: "A standup is summarized into decisions and owners"
tags: [notes:summarize]
runs: 3
allowed_tools: [Read, Skill]
expected_outcome: "Each decision is listed with its owner"
---

Summarize who owns what from this standup: Priya ships the export fix Friday; Omar owns the
release notes.
MD

cat >my-plugin/evals/summarize-standup/graders/skill-fired.md <<'MD'
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:notes:)?summarize"'
min: 1
---
MD
