---
description: "compress when the repository's lint ignores the paths it is given: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that always lints every markdown file in the tree and prints '<file>: <rule>' for each failure; docs/style.md fails it before any edit and docs/onboarding.md passes. Passing the file cannot scope it, so the run must take a baseline run before the edit, compare by file and rule, see docs/style.md's failure is in the baseline and not the target's, keep the compression, and report the target compressed with lint=PASS, never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('Run that same scoped command once before the first edit as a baseline'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold, baseline]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Reads scripts/lint-md.sh and sees it ignores its arguments, runs lint:md once before editing as the baseline, edits docs/onboarding.md, runs lint:md again, finds only docs/style.md's baseline failure, keeps the compression, and the summary line carries compressed and lint=PASS."
---

/docs-hygiene:compress docs/onboarding.md
