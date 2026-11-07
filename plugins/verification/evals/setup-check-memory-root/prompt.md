---
description: 'Legacy setup 1. A bare /verification:setup is check: it reports the memory root (.work/, none declared) as INFO, probes a representative file path under it with git check-ignore -v, runs setup-apply.mjs --check, and writes nothing (setup SKILL.md check steps 1-3). The scaffold makes a committed repository whose AGENTS.md binds docs/conventions. runs-check grades the --check call, probes-file-path a check-ignore on a path below .work/ (not the bare directory), memory-root-info the INFO row naming .work/, no-settings-file, no-ignore-write, no-ignore-shell-write and no-verification-pass that nothing is written and no verification skill runs. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, setup, check, scaffold, no-network, routine]
max_turns: 15
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'A PASS/INFO/WARN table: the memory root .work/ as INFO, a git check-ignore -v probe of a file under it, the settings-file row from setup-apply.mjs --check; nothing written and no verification pass run.'
---

/verification:setup
