---
description: "check in a git repository with a workflow and no .github/actionlint.yaml. setup SKILL.md check step 4: lint.sh --resolve reports the actionlint adapter with no config (actionlint runs on its defaults), and an absent config is not a fault; the plugin writes no actionlint config. The real reasons lint does not run: step 7 (the scaffold installs no pre-commit entry, so verify reports missing and the fix is apply install-git-hooks), step 5 (actionlint_end_of_turn defaults to false, so only the pre-commit entry lints), steps 2-3 (node or actionlint missing) and the toggle. The scaffold creates no actionlint config, so the file_exists graders catch a write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [actionlint, setup, check, read-only]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No actionlint config is written and none is offered; the reply says the absent config is INFO, not FAIL, since actionlint auto-discovers an optional config and runs with built-in defaults, so it is not why lint is not happening, and names a real cause such as the missing pre-commit entry."
---

/actionlint:setup check

This repository has no .github/actionlint.yaml. Is that why workflow lint is not happening?
