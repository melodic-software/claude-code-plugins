---
description: "compress when the repository's lint fails on another file only: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that fails any markdown file whose first line is not an ATX heading; docs/style.md fails it and docs/onboarding.md passes. The run must edit docs/onboarding.md, run the script scoped to it (the file passed, or a baseline before the edit), keep the compression, and report the target compressed with lint=PASS, never reverting on docs/style.md's failure and never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('never revert on another file's failure'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs the repository's lint:md script scoped to it or against a baseline, sees docs/style.md's failure is not new and not the target's, keeps the compression, and the summary line carries compressed and lint=PASS."
---

/docs-hygiene:compress docs/onboarding.md
