---
description: "A repository whose default branch sets verification: standard in docs/conventions/discipline.yaml: /discipline:mind-your-maxims audits a load-bearing code change and dispatches a fresh-context subagent, to confirm a clean audit (step 2) or re-derive a finding (step 3). Needs --scaffold --allow-tools Bash Agent."
tags: [mind-your-maxims, setting, verification-level, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: standard from docs/conventions/discipline.yaml at origin/main, audits the branch change, dispatches a fresh-context subagent, and writes no skip token"
---

I am about to merge this branch: the commit on feat/strip-punctuation (`git diff main`) makes slugify strip punctuation, and it ships. /discipline:mind-your-maxims
