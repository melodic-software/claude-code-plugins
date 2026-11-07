---
description: "Legacy lint 3. `/toolchain:lint all` runs the lint-only surfaces /toolchain:check never runs: yaml for the changed workflow file, and cross-cutting because text files changed and the repository opts in (_typos.toml at the root). Every other ecosystem is disabled so the run does not depend on host tools. yaml-ran and cross-cutting-ran read .calls.log; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, yaml, cross-cutting, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The tracked yaml config's check command and the tracked cross-cutting config's check command both run; the reply reports a yaml row and a cross-cutting row."
---

/toolchain:lint all
