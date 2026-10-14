#!/usr/bin/env bash
# Seed a notes plugin whose eval suite has one case with an unknown frontmatter key.
set -euo pipefail

mkdir -p my-plugin/.claude-plugin my-plugin/skills/summarize \
  my-plugin/evals/summarize-meeting/graders my-plugin/evals/tag-notes/graders

cat >my-plugin/.claude-plugin/plugin.json <<'JSON'
{
  "name": "notes",
  "version": "0.1.0",
  "description": "Summarize and tag meeting notes"
}
JSON

cat >my-plugin/skills/summarize/SKILL.md <<'MD'
---
description: "Summarize meeting notes into decisions and owners. Use when asked to summarize a meeting or standup."
---

# Summarize meeting notes

List each decision with its owner, then open questions.
MD

cat >my-plugin/evals/summarize-meeting/prompt.md <<'MD'
---
description: "A standup transcript is summarized into decisions and owners"
tags: [summarize]
runs: 3
timeout: 120
allowed_tools: [Read, Skill]
expected_outcome: "Each decision is listed with its owner"
---

Summarize the decisions and who owns each one from this standup: Priya will ship the export fix
Friday; we agreed to drop the beta flag; Omar owns the release notes.
MD

cat >my-plugin/evals/summarize-meeting/graders/skill-fired.md <<'MD'
---
type: tool_used
tool: Skill
input_match: "summarize"
---
MD

cat >my-plugin/evals/tag-notes/prompt.md <<'MD'
---
description: "Notes about a release get a release tag"
tags: [tags]
runs: 3
timeout_seconds: 300
allowed_tools: [Read]
expected_outcome: "The reply suggests the tag release"
---

Suggest one tag for these notes: release 2.4 ships Thursday, changelog is drafted.
MD

cat >my-plugin/evals/tag-notes/graders/release-tag.md <<'MD'
---
type: regex
flags: i
---

\brelease\b
MD
