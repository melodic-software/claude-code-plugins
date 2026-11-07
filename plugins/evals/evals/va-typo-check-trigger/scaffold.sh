#!/usr/bin/env bash
# Seed a notes plugin whose suite has one load-time FAIL (grader type: contains) and one
# authoring WARN (a regex grader on target: files).
set -euo pipefail

mkdir -p my-plugin/.claude-plugin my-plugin/skills/summarize \
  my-plugin/evals/summarize-standup/graders my-plugin/evals/export-notes

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

cat >my-plugin/evals/summarize-standup/prompt.md <<'MD'
---
description: "A standup is summarized into decisions and owners"
runs: 3
allowed_tools: [Read, Skill]
expected_outcome: "Each decision is listed with its owner"
---

Summarize who owns what from this standup: Priya ships the export fix Friday; Omar owns the
release notes.
MD

cat >my-plugin/evals/summarize-standup/graders/owner-named.md <<'MD'
---
type: contains
pattern: "Omar"
---
MD

cat >my-plugin/evals/export-notes/case.yaml <<'YAML'
schema_version: "1.1"
name: export-notes
expected_outcome: "The notes are written to notes/summary.md and name both owners"
execution:
  prompt: "Write a summary of this standup to notes/summary.md: Priya ships the export fix Friday; Omar owns the release notes."
  allowed_tools: [Read, Write, Skill]
graders:
  - name: names-owners
    type: regex
    pattern: 'Priya[\s\S]*Omar'
    target: files
YAML
