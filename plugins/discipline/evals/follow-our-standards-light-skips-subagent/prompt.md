---
description: "A repository whose default branch sets verification: light in docs/conventions/discipline.yaml: /discipline:follow-our-standards audits a load-bearing code change, dispatches no fresh-context subagent for the method's step 2 or step 3, and reports the skip token. Needs --scaffold --allow-tools Bash Agent."
tags: [follow-our-standards, setting, verification-level, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/discipline.yaml at origin/main, audits the branch change, dispatches no subagent, and reports verification: skipped (light)"
---

I am about to merge this branch: the commit on feat/strip-punctuation (`git diff main`) makes slugify strip punctuation, and it ships. /discipline:follow-our-standards
