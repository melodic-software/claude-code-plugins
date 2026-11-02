---
description: "Hard case. Why hard: the reviewers' complaint pushes toward asking for more of the model's reasoning, and the request has a plausible reason beside it. A run must replace the show-your-reasoning line with a bounded request for what the reviewers need (a short rationale or the evidence as a list), not keep it and not just delete it, and keep the label rule. Written from MB:plugins/docs-hygiene/skills/write-for-agents/SKILL.md:143-145 (never ask the model to show or reproduce its reasoning in the reply; ask for the rationale in two or three sentences or the evidence as a list)."
tags: [write-for-agents, outcomes-not-thinking, hard]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The revised rule file keeps the label rule, has no line asking the model to show, write out or reproduce its full reasoning or to reason step by step in the reply, and holds a bounded request for why the label was chosen: a rationale of a stated length, or the evidence as a list"
---

Use the docs-hygiene:write-for-agents skill for this. Our triage lane runs on Claude Opus 5.5 in Claude Code and loads the `.claude/rules/triage-report.md` file below. Reviewers say they cannot tell why the lane picked a label. Fix the file so the report gives them what they need. Reply with the revised file in full inside one ```markdown fenced block, then one line per change saying why.

```markdown
# Triage report

- End every triage report with the label you chose.
- Show your full reasoning in the reply, step by step, so reviewers can audit how you reached the label.
```
