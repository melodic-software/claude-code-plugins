---
description: "compress when a whole-tree lint run is clean before the edit and, after it, names a new failure in another file: the scaffold's package.json declares a lint:md script (bash scripts/lint-md.sh) that ignores its arguments, lints the whole tree, and fails docs/style.md when docs/onboarding.md, the page docs/style.md cites in docs/refs.lock, no longer matches its reviewed checksum, naming docs/style.md and never docs/onboarding.md. The baseline run exits 0, so any compression adds a failure in docs/style.md. The run must edit docs/onboarding.md, revert it, and report the target reverted with lint=FAIL, never lint=PASS, and never run markdownlint. Written from the compress Hard rules 'Post-edit markdown lint must pass' ('When a run of the whole command names a failure in a file that is not the target ... revert the target, report lint=FAIL'). Needs --scaffold --allow-tools Bash Write Edit."
tags: [compress, lint, ecosystem-resolution, scaffold, revert]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Edits docs/onboarding.md, runs lint:md whole before and after the edit, sees a new failure named in docs/style.md with no other target edited, restores docs/onboarding.md to its original text, and the summary line carries reverted and lint=FAIL."
---

/docs-hygiene:compress docs/onboarding.md
