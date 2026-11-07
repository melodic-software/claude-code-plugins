---
description: 'Legacy setup 3. Before any verification run .work/ does not exist and no rule ignores it, so the ignore probe is INFO, not FAIL: the memory root''s self-ignoring .gitignore is created by the first memory-slice write; check creates neither the directory nor the guard (setup SKILL.md check step 2). The scaffold makes a committed repository with no .gitignore and no .work/. ignore-row-info grades an INFO ignore row, no-ignore-fail no FAIL on it, no-memory-root no .work/ created, no-ignore-write and no-ignore-shell-write no ignore file written; first-write-creates-guard (llm) legacy expectation 2 verbatim. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, setup, check, scaffold, no-network, routine]
max_turns: 15
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The ignore probe row is INFO, explained by the first memory-slice write creating .work/.gitignore; no .work/ directory or .gitignore is created.'
---

/verification:setup check

No verification run has happened in this repo yet, so .work/ does not exist.
