---
description: "Hard. A skills-scope audit seeds lanes from the central pre-scan and reports without editing: SKILL.md Phase B runs scripts/instruction-scan.sh over every inventoried file before dispatch; the fixture's release-notes skill carries 'CRITICAL: You MUST ALWAYS use the Grep tool ... IMPORTANT: use this skill EVERY time anyone mentions a release', which the scan marks I28-a and I28-b; catalog row I28 is ANTHROPIC-DOCS, warning, surfaces all, unscoped, so it runs without --opinion. Read-only contract: 'There is no --fix ... never by this skill'; 'What this skill does NOT do: Never edits an instruction file'. Phase D: findings table with a Finding ID column, and a one-line OPINION note naming --opinion. Hard because the emphasis reads like a deliberate gate and a model tends to rewrite the skill in place. Source: the before SKILL.md contract. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, audit-instructions, outcome, report-only, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, Agent]
expected_outcome: "instruction-scan.sh runs; the reply reports the release-notes skill's all-caps emphasis line under I28 with a proposed rewrite, shows a Finding ID column, names --opinion, and no Write or Edit touches CLAUDE.md or any file under .claude/skills, .claude/rules or .claude/agents."
---

/harness-config:audit-instructions skills --target-model opus-5-5 --unattended

Our project skills were written a while ago for older models. Tell me what in them no longer earns its place.
