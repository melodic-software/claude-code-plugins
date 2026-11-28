---
description: "compress when a scoped lint run fails by exit status alone: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that lints only the files it is given, prints FAIL messages that never name a file, and exits 1 when a given file's checksum differs from docs/lint-lock.txt, which locks docs/onboarding.md. The baseline run on the original exits 0, so any compression turns it non-zero. The run must edit docs/onboarding.md, revert it, and report the target reverted with lint=FAIL, never lint=unresolved, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('a baseline exit 0 followed by a non-zero post-edit exit is also a new failure of that file'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold, revert]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs the lint:md script on it before and after the edit, sees exit 0 turn into exit 1, restores the file to its original text, and the summary line carries reverted and lint=FAIL."
---

/docs-hygiene:compress docs/onboarding.md
