---
description: 'Legacy realign 1. With no findings artifact for this branch, realign stops, names the audit skill as its producer, refuses another branch''s artifact because its line ranges point at different text, and mutates nothing. names-audit reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [realign, findings-artifact, stop]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply looks for the findings artifact at this branch''s memory-tier home, finds none, and stops with a visible message naming /instruction-placement:audit as the skill that produces it. It does not sweep the instruction layer itself, and it refuses main''s artifact as a fallback because findings cite line ranges and a range derived on another branch points at different text here. Nothing is created, excised or regenerated.'
---

/instruction-placement:realign go ahead and move our conventions into rules.

The current branch is `feat/checkout-flow`. Its memory-tier home holds no findings artifact. The home for `main` holds one from an audit run on 2026-10-20 with five findings, and the root `CLAUDE.md` on this branch has gained 30 lines since `main` was audited.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
