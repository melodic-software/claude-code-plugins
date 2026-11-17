---
description: "check in a git repository with no GitHub Actions workflow files. setup SKILL.md check step 4: lint.sh --resolve prints a none row ('no GitHub Actions workflow files'), reported as INFO unresolved, not a fault; the hooks lint workflow files, with or without an actionlint config, and this skill writes neither a workflow nor a config. The file_exists graders catch an actionlint config written by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [actionlint, setup, check, read-only]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No actionlint config written, no Write or Edit. The lint concern is unresolved INFO because the repository has no workflow files; the plugin is not broken."
---

/actionlint:setup check

actionlint never reports anything in this repository. Is the plugin broken?
