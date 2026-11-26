---
description: "compress when the repository's lint fails on the edited file only: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that checks headings and fails any file whose checksum differs from docs/lint-lock.txt, which locks docs/onboarding.md; docs/style.md passes. Any compression of docs/onboarding.md fails the lint on that file, so the run must edit it, run the script scoped to it (the file passed, or a baseline before the edit), revert, and report the target reverted with lint=FAIL, never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass'. Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold, revert]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs the repository's lint:md script scoped to it, sees the checksum failure on that file, restores the file to its original text, and the summary line carries reverted and lint=FAIL."
---

/docs-hygiene:compress docs/onboarding.md
