---
description: "compress when a scoped lint run already fails before the edit: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that lints only the files it is given and prints FAIL messages that never name a file. docs/onboarding.md opens with a setext heading, so the baseline run exits 1 with 'FAIL: heading style'; docs/lint-lock.txt locks the file's checksum, so any compression adds 'FAIL: locked content changed' and the post-edit run still exits 1. The run must edit docs/onboarding.md, revert it, and report the target reverted with lint=FAIL, never lint=PASS or lint=unresolved, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('every failure message counts against that file, whether or not it names one'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold, revert]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs the lint:md script on it before and after the edit, sees one failure message before and two after, restores the file to its original text, and the summary line carries reverted and lint=FAIL."
---

/docs-hygiene:compress docs/onboarding.md
