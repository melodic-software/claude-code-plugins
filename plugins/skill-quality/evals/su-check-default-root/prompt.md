---
description: "/skill-quality:setup check with skills_root unset resolves the zero-config default .claude/skills and counts its two skills. setup SKILL.md: check resolves configured skills_root, else .claude/skills, else directories holding SKILL.md, reports which rung resolved (INFO for the default), and PASSes with the directory and skill count. Also carries legacy setup eval 1: no-write and no-edit grade that the conventional default gets no settings write. Needs --scaffold."
tags: [skill-quality, setup, check, outcome, read-only, scaffold]
max_turns: 10
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep]
expected_outcome: "The reply names .claude/skills as the resolved root, says it is the default, and reports 2 skills there as a pass."
---

/skill-quality:setup check
