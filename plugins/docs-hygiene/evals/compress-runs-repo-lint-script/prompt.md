---
description: "compress with a resolvable markdown lint command: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh, an offline heading check) and nothing names markdownlint. The run must compress docs/onboarding.md, run that script (through the package manager or directly), report lint=PASS, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' and reference/ecosystem-resolution.md step 4. Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md to cut its filler, runs the repository's lint:md script (npm run lint:md or scripts/lint-md.sh) on it, runs no markdownlint command, and the summary line carries lint=PASS."
---

/docs-hygiene:compress docs/onboarding.md
