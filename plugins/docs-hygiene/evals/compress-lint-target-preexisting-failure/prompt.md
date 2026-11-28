---
description: "compress when the target itself already fails lint before the edit and the edit adds no failure: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that lints only the files it is given, needs an ATX first heading and an owner marker line in each, and names the file and rule in each failure. docs/onboarding.md has no owner marker, so the scoped baseline run reports `docs/onboarding.md: owner-marker` and exits 1; a compression edit leaves that one failure and adds none. The run must edit docs/onboarding.md, keep the compression, report it compressed with lint=PASS, say that the target already failed lint before the edit, and never run markdownlint. This is the first loosened case in PR 19128's `## Loosened checks`, which main's markdownlint-cli2 gate reverted. Written from the compress Hard rules 'Post-edit markdown lint must pass' (count failures per file and rule against the baseline) and the output schema ('when the target already failed before the edit, say so after its line'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Runs lint:md on docs/onboarding.md before and after the edit, sees the same owner-marker failure both times and no new one, keeps the compression, and the reply carries compressed and lint=PASS and says the target already failed lint before the edit."
---

/docs-hygiene:compress docs/onboarding.md
