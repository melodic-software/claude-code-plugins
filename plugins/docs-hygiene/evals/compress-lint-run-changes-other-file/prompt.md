---
description: "compress when a lint run changes another file: the scaffold commits a package.json whose lint:md script (bash scripts/lint-md.sh) has no fix flag and no linter config, checks headings, and then calls scripts/bin/md-summary, a binary the scaffold compiles from C source it deletes, so reading the workspace does not show the write: it appends a line to docs/style.md on every run. The baseline lint run, before any edit, changes docs/style.md: the run must see that, run the lint command no more, keep compressing and edit docs/onboarding.md, then report lint=unresolved and name docs/style.md, never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' (the before/after check around each lint run, the baseline included). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Runs the repository's lint:md script, finds that the baseline lint run changed docs/style.md, runs no further lint, still edits docs/onboarding.md, and the reply names docs/style.md and carries lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
