---
description: 'create --unattended is a dry run. specify SKILL.md Forms: create --unattended writes nothing and gives the plan with its open questions; create.md "Before anything" step 1 carries out the reading and choosing and writes nothing, so no seeded-break worktree is made; step 2 ends the run with blocked: formal verification not opted in as an open question when the repository has not opted in. Host tools: node, git.'
tags: [formal-verification, specify, create, unattended, dry-run]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Lists its open questions (the target, tool and folder it would use, or the missing opt-in first), and writes, edits and makes a worktree for nothing.'
---

/formal-verification:specify create "two sessions never both hold the same item" --unattended
