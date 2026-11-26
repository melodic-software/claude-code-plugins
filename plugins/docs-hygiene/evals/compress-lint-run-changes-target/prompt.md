---
description: "compress when a lint run changes the target itself: the scaffold commits a package.json whose lint:md script (bash scripts/lint-md.sh) has no fix flag and no linter config, checks headings, and then calls scripts/lib/summary.sh, which appends a 'Last checked by lint-md.' line to every file it checked. The run must edit docs/onboarding.md, see after the lint run that docs/onboarding.md changed, restore it to the bytes it held just before that lint run (the compressed text, not the committed original), stop, report lint=unresolved and name docs/onboarding.md, never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' (the before/after check of each lint run and its restore of a changed target). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs or inspects the repository's lint:md script, finds that a lint run changed docs/onboarding.md, restores the compressed text without the linter's line and without going back to the committed original, stops, and the reply names docs/onboarding.md as changed and carries lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
