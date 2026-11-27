---
description: "compress when the repository's lint command cannot be scoped and passes: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that ignores its arguments, lints the whole tree and prints only a count, never a file name; every markdown file opens with an ATX heading, so it exits 0 before and after the edit. The run must edit docs/onboarding.md, keep the compression, and report the target compressed with lint=PASS, never lint=unresolved, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('A post-edit run of the whole command that exits 0 is a pass for every target'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs lint:md whole before and after the edit, sees exit 0 both times, keeps the compression, and the summary line carries compressed and lint=PASS."
---

/docs-hygiene:compress docs/onboarding.md
