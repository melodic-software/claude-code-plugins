---
description: "compress with no resolvable markdown linter: the scaffold has no ecosystem record, no stated lint command, no manifest and no linter config. The run must compress docs/onboarding.md anyway (no stop at the entry point), report lint=unresolved, and never run, probe or install a linter of its own choosing such as markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' and reference/ecosystem-resolution.md step 7. Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md to cut its filler, runs no markdownlint command and installs nothing, and the summary line carries lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
