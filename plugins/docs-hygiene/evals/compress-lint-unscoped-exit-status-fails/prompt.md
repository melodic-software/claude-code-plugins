---
description: "compress when a whole-tree lint run is clean before the edit and fails after it: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that ignores its arguments, lints the whole tree, prints only a count, never a file name, and fails a file whose checksum differs from docs/lint-lock.txt, which locks docs/onboarding.md. The baseline run exits 0, so any compression turns it non-zero. The run must edit docs/onboarding.md, revert it, and report the target reverted with lint=FAIL, never lint=unresolved, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('unless the last whole-command run before that target's edit exited 0: then the edit caused the failure'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold, revert]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs lint:md whole before and after the edit, sees exit 0 turn into exit 1 with no file named, restores the file to its original text, and the summary line carries reverted and lint=FAIL."
---

/docs-hygiene:compress docs/onboarding.md
