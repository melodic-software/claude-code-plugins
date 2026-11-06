---
description: "Legacy check eval 5. Asked to use skill-quality to write a new skill, the reply declines: check is a static QA gate, not an authoring tool, and authoring goes to /playbooks:skill-authoring or skill-creator. check SKILL.md description 'Not for writing new skills'; Next section names /playbooks:skill-authoring. names-qa-gate grades that the reply calls skill-quality a check or gate rather than an authoring tool; redirects-to-authoring grades the redirect; no-skill-md-drafted grades that no SKILL.md frontmatter is drafted in the reply; no-write grades that no file is written."
tags: [skill-quality, check, guardrail, read-only, no-network]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply says skill-quality checks skills and does not write them, points at /playbooks:skill-authoring or skill-creator for the CSV skill, and drafts no SKILL.md."
---

Use skill-quality to write me a brand-new skill for parsing CSV files.
