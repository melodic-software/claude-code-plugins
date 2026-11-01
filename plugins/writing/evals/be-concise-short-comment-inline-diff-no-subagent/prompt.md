---
tags: ['be-concise']
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Handles a four-line comment inline. Shows the before and after in the reply itself and dispatches no semantic-diff subagent, because a fresh-context round trip costs more than the message it would verify. The rewrite cuts the hedges and filler (''just wanted to quickly mention'', ''actually'', ''perfectly fine'', ''so far as I can tell'', ''obviously'', ''at all'') while keeping all three facts: the retry patch is merged, it is healthy in staging, and the author wants to hear concerns. Before and after word counts are reported.'
---

Make this standup comment less waffly: short-standup-comment.md.
