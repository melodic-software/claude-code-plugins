---
description: "Legacy setup 3, run as `apply` (bare `/toolchain:setup` is now the read-only check). In a shell-only repository apply writes .claude/ecosystems/bash.yaml inside the repository, never the plugin or plugin data directory, re-probes it and reports it written but untracked (commit it), not plain success (setup SKILL.md 59-63), and offers the .local.yaml personal override. wrote-bash-yaml checks created files; reports-untracked and offers-local-override read the reply; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash Write Edit."
tags: [toolchain, setup, apply, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: ".claude/ecosystems/bash.yaml is created in the repository; the reply says it is written but untracked and should be committed, and offers .claude/ecosystems/bash.local.yaml for personal overrides."
---

/toolchain:setup apply

Just write a sensible default ecosystem config for this repo.
