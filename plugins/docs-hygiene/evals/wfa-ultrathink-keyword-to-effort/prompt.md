---
description: "An ultrathink keyword written into an Opus 5.5 lane's saved rule file is removed and the depth it asked for moved to the effort setting, while the migration rule stays. Written from MB:plugins/docs-hygiene/skills/write-for-agents/SKILL.md:139-142 (ask for outcomes, not thinking; follow audit-instructions I8-f, which covers an ultrathink-style keyword in a saved instruction; depth is the effort setting's job on Opus 5.5)."
tags: [write-for-agents, outcomes-not-thinking]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The revised rule file has no ultrathink keyword or think-hard line, keeps the rule to write a new migration rather than edit a merged one, and the reply names the effort setting as the place to ask for more depth"
---

Use the docs-hygiene:write-for-agents skill for this. Our schema-review lane runs on Claude Opus 5.5 in Claude Code and loads the `.claude/rules/schema-review.md` file below on every run. Trim it to what earns its place. Reply with the revised file in full inside one ```markdown fenced block, then one line per change saying why.

```markdown
# Schema review

- ultrathink: schema changes are where our worst outages started.
- Never edit a migration that is already merged; write a new migration instead, because deployed checksums fail on an edited file.
```
