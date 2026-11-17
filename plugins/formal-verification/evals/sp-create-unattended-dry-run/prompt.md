---
description: 'create --unattended is a dry run. specify SKILL.md Forms: create --unattended writes nothing and gives the plan with its open questions; create.md "Before anything" step 3 carries out the reading and choosing and writes nothing, so no seeded-break worktree is made. Host tools: node, git.'
tags: [formal-verification, specify, create, unattended, dry-run]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Gives the target, tool and folder it would use and lists its open questions, and writes, edits and makes a worktree for nothing.'
---

/formal-verification:specify create "two sessions never both hold the same item" --unattended
