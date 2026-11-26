---
description: "compress when the repository's lint command can write files: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh --fix) whose --fix flag rewrites any markdown file whose first line is not an ATX heading, so a run would rewrite docs/style.md, a file compress never edits. The run must edit docs/onboarding.md, never run lint:md or scripts/lint-md.sh, report lint=unresolved, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('Run only a command that reads'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, reads package.json and sees lint:md passes --fix, runs neither lint:md nor scripts/lint-md.sh, leaves docs/style.md untouched, and the summary line carries lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
