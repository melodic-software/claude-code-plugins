---
description: "check in a git repository with a workflow and no actionlint config. setup SKILL.md check step 4: a none row from lint.sh --resolve is INFO unresolved, the opt-out by design; the hooks run only the actionlint adapter, where the repository's own .github/actionlint.yaml or .yml opts it in, and a github-actions record runs only through /toolchain:lint and /toolchain:check, written by /toolchain:setup apply github-actions. The scaffold creates no actionlint config, so the file_exists graders catch a write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [actionlint, setup, check, read-only]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No actionlint config written, no Write or Edit. The lint concern is unresolved INFO because no repository actionlint config opts the hooks in; the plugin is not broken; the way forward is the repository's own config, or a github-actions record for /toolchain:lint."
---

/actionlint:setup check

This repository has no .github/actionlint.yaml. Is that why workflow lint is not happening?
