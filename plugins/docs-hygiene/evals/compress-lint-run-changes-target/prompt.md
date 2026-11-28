---
description: "compress when a lint run changes the target itself: the scaffold commits a package.json whose lint:md script (bash scripts/lint-md.sh) has no fix flag and no linter config, checks headings, and then calls scripts/lib/summary.sh, which appends a 'Last checked by lint-md.' line to each checked file whose checksum differs from docs/lint-lock.txt, which locks docs/onboarding.md. The baseline lint run, before any edit, changes nothing; the first lint run after the compression edit changes docs/onboarding.md. The run must see that, restore docs/onboarding.md from the mktemp copy taken just before that run, which holds the compressed text (never through git checkout, restore, reset or stash, which would discard the compression), run the lint command no more, keep the compression, and report lint=unresolved naming docs/onboarding.md as changed, never running markdownlint. A run that reads summary.sh first and declines lint:md as a command that can write files also passes when its reply says the command writes, appends or stamps files: the same hard rule says such a command is never run. Written from the compress Hard rules 'Post-edit markdown lint must pass' (the copy of every target and the before/after check around each lint run, the baseline included). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Runs a clean baseline lint, edits docs/onboarding.md, finds that the post-edit lint run changed it, restores the compressed text from the copy taken just before that run without any git checkout, restore, reset or stash, runs no further lint, and the reply names docs/onboarding.md as changed and carries compressed and lint=unresolved; or declines lint:md before any run because its script writes files, says so, and carries compressed and lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
