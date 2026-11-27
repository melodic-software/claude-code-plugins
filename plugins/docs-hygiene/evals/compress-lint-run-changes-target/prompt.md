---
description: "compress when a lint run changes the target itself: the scaffold commits a package.json whose lint:md script (bash scripts/lint-md.sh) has no fix flag and no linter config, checks headings, and then calls scripts/lib/summary.sh, which appends a 'Last checked by lint-md.' line to every file it checked. The baseline lint run, before any edit, changes docs/onboarding.md: the run must see that, restore docs/onboarding.md from the mktemp copy taken just before that run (never through git checkout, restore, reset or stash), run the lint command no more, keep compressing and edit docs/onboarding.md, then report lint=unresolved and name docs/onboarding.md as changed, never running markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' (the copy of every target and the before/after check around each lint run, the baseline included). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Runs or inspects the repository's lint:md script, finds that the baseline lint run changed docs/onboarding.md, restores it from the copy taken just before that run without any git checkout, restore, reset or stash, runs no further lint, still edits docs/onboarding.md, and the reply names docs/onboarding.md as changed and carries lint=unresolved."
---

/docs-hygiene:compress docs/onboarding.md
