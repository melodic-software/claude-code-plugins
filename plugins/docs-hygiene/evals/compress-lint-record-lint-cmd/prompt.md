---
description: "compress with a markdown ecosystem record: docs/conventions/ecosystems/markdown.yaml holds a read-only lint-cmd (bash scripts/check-md.sh) and a write-capable fix-cmd (bash scripts/fix-md.sh), and package.json also declares a lint:md script (bash scripts/lint-md.sh) that always fails. The run must compress docs/onboarding.md, run the record's lint-cmd, never run its fix-cmd or the manifest script, report lint=PASS, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' (a record's fix-cmd is never run) and reference/ecosystem-resolution.md step 2 (the record is read before anything is stated or inferred). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md to cut its filler, runs the record's lint-cmd (bash scripts/check-md.sh) on it, runs neither scripts/fix-md.sh nor the lint:md script, runs no markdownlint command, and the summary line carries lint=PASS."
---

/docs-hygiene:compress docs/onboarding.md
