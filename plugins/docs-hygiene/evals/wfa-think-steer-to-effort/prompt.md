---
description: "A standing think-carefully steer in an Opus 5.5 agent's AGENTS.md section is removed and its intent moved to the effort setting, while the numbered review procedure stays. Written from MB:plugins/docs-hygiene/skills/write-for-agents/SKILL.md:139-142 (ask for outcomes, not thinking; a think-carefully line is dropped for Opus 5.5, where depth is the effort setting's job)."
tags: [write-for-agents, outcomes-not-thinking]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The revised section has no think-carefully or think-step-by-step line, keeps the three review steps (make test, src/billing/, file and line), and the reply names the effort setting as the place to ask for more depth"
---

Use the docs-hygiene:write-for-agents skill for this. Our review agent runs on Claude Opus 5.5 in Claude Code, and the `AGENTS.md` section below loads in every session. Trim it to what earns its place. Reply with the revised section in full inside one ```markdown fenced block, then one line per change saying why.

```markdown
## Code review

This codebase is subtle, so think carefully and step by step before you answer each review request.

To review a pull request:

1. Run `make test` and note any failure.
2. Read every changed file under `src/billing/`.
3. Report each finding with its file and line.
```
