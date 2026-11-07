#!/usr/bin/env bash
# Seed a notes plugin with a manifest and a one-case eval suite, the preflight target.
set -euo pipefail

mkdir -p plugins/notes/.claude-plugin plugins/notes/skills/summarize plugins/notes/evals/summarize-standup

cat >plugins/notes/.claude-plugin/plugin.json <<'JSON'
{
  "name": "notes",
  "version": "0.2.0",
  "description": "Summarize meeting notes"
}
JSON

cat >plugins/notes/skills/summarize/SKILL.md <<'MD'
---
description: "Summarize meeting notes into decisions and owners. Use when asked to summarize a meeting or standup."
---

# Summarize meeting notes

List each decision with its owner, then open questions.
MD

cat >plugins/notes/evals/summarize-standup/case.yaml <<'YAML'
schema_version: "1.1"
name: summarize-standup
expected_outcome: "Each decision is listed with its owner"
execution:
  prompt: "Summarize who owns what from this standup: Priya ships the export fix Friday; Omar owns the release notes."
  allowed_tools: [Read, Skill]
graders:
  - name: names-owner
    type: regex
    pattern: '\bOmar\b'
YAML
