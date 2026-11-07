---
description: "Legacy setup 4, run as `apply typescript` (bare `/toolchain:setup typescript` names no action now; setup SKILL.md 23-26). The package.json has both a `test` and a `test:ci` script and no linter config, so inference is ambiguous: the skill asks which command to use instead of guessing, writes no typescript.yaml, and stays scoped to typescript (no python.yaml either). no-typescript-file and no-python-file check created files, names-test-ci the reply; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash Write Edit."
tags: [toolchain, setup, apply, ambiguous, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply asks which of the test and test:ci scripts (and which linter, if any) to use; no .claude/ecosystems/typescript.yaml or python.yaml is created."
---

/toolchain:setup apply typescript
