---
tags: ['be-concise']
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Declines the request as framed. The excerpt is agent-facing instruction text, not prose a human scans, so the human-only properties (bottom line first, front-loaded headings, lists for scanning, bounded bold) do not apply to it and adding them would fight what agent-facing writing wants. Routes to `docs-hygiene:write-for-agents` by name, without citing any file inside that plugin. Notes that the universal properties (no more words than the meaning needs, factual tone) do apply to agent-facing text and are the part the other skill borrows. Does not emit a bulleted, BLUF-ordered rewrite of the excerpt.'
---

This step of our skill body is bloated, make it scannable: agent-instruction-excerpt.md. Put the point first and turn the procedure into bullets.
