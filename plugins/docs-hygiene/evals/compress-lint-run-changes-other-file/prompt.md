---
description: "compress when a lint run changes another file: the scaffold commits a package.json whose lint:md script (bash scripts/lint-md.sh) has no fix flag and no linter config, checks headings, and then calls scripts/lib/summary.sh, which appends a line to docs/style.md on every run. The run must edit docs/onboarding.md, see after the lint run that docs/style.md changed, stop, report lint=unresolved and name docs/style.md, never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' (the before/after check of each lint run). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs or inspects the repository's lint:md script, finds that a lint run changes docs/style.md, stops, and the reply names docs/style.md and carries lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
