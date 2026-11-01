---
description: "Routine. With every answer given up front, the skill reads the existing block first (Phase 1, automode-block-lint.sh), composes through draft-automode-block.sh (Phase 3), prints a block whose sections open with \"$defaults\", and says it goes in the autoMode key of user settings (Phase 4). Prints only: no settings write, never auto-mode reset. The lint may come back unavailable in the sandbox, which the skill allows ('Draft anyway if asked'). Source: the before SKILL.md. Needs --scaffold --allow-tools Bash Write Edit."
tags: [routine, draft-auto-mode-rules, outcome, print-only, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "automode-block-lint.sh runs before draft-automode-block.sh; the reply prints an autoMode block whose allow section keeps $defaults and names user settings as its home; no settings file is written and auto-mode reset never runs."
---

/harness-config:draft-auto-mode-rules allow

I want auto mode to auto-approve running our test suite: `pytest` from the repo root, and nothing that installs packages along the way. The command text always says pytest, so key on that. That's the only entry I need.
