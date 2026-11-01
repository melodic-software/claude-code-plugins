---
description: "Routine. Phase 1 step 1: 'refuse to start on a dirty tree or on the default branch. Create or confirm a dedicated branch'; every mutating step waits for confirmation. The fixture is on main. Whether the skill refuses outright or first moves to a dedicated experiment branch is not settled by the text, so the graders check only that nothing is stripped, committed or deleted. Source: the before SKILL.md. Needs --scaffold --allow-tools Bash Write Edit WebFetch."
tags: [routine, unhobble, outcome, gate, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, WebFetch]
expected_outcome: "Nothing is stripped on main: no git rm, no strip commit, no instruction file deleted or edited; the reply names the default branch or a dedicated experiment branch."
---

/harness-config:unhobble snapshot

A new model just shipped. Let's see which of our instructions it still needs.
