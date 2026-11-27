---
description: "compress when the repository's lint command cannot be scoped: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that ignores its arguments, lints the whole tree and prints only a count, never a file name; docs/style.md fails it, before and after any edit. The run must edit docs/onboarding.md, keep the compression, and report the target compressed with lint=unresolved, never reverting on a failure it cannot tie to the target and never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('When a run of the whole command fails and names no file in its output, report lint=unresolved'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, sees lint:md neither takes paths nor names a failing file, keeps the compression, and the summary line carries compressed and lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
