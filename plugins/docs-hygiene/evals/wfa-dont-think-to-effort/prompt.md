---
description: "A don't-think line in an Opus 5.5 lane's rule file, written to make replies faster, is removed and the speed goal moved to a lower effort level, while the two content rules stay. Written from MB:plugins/docs-hygiene/skills/write-for-agents/SKILL.md:140-143 (a line telling the model to think less or not at all follows audit-instructions I8-c per model; a quick answer is a lower effort level first, \"Answer directly.\" second)."
tags: [write-for-agents, outcomes-not-thinking]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The revised rule file has no line telling the model not to think or to skip its thinking, keeps the customer's-language and help-center-link rules, and the reply names a lower effort level as the way to make replies faster"
---

Our support-reply lane runs on Claude Opus 5.5 in Claude Code and loads the `.claude/rules/support-replies.md` file below. Its replies are slow to start. Fix the file. Reply with the revised file in full inside one ```markdown fenced block, then one line per change saying why.

```markdown
# Support replies

- Don't think, just answer: speed matters more than polish here.
- Reply in the customer's language.
- Link the help-center article you used.
```
