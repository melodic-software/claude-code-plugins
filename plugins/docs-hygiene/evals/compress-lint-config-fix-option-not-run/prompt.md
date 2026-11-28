---
description: "compress when the repository's lint can write files through its config: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) with no --fix flag, but the script reads .lintmdrc.json, which sets \"fix\": true, so a run would rewrite docs/style.md, a file compress never edits. The run must edit docs/onboarding.md, never run lint:md or scripts/lint-md.sh, report lint=unresolved, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('a fix or write option in the config file its linter reads'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, reads scripts/lint-md.sh and .lintmdrc.json and sees the config turns on fixing, runs neither lint:md nor scripts/lint-md.sh, leaves docs/style.md untouched, and the summary line carries lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
