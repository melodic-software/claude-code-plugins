---
description: "Legacy setup 1, run as `apply` because bare `/toolchain:setup` is now the read-only check (setup SKILL.md 23-26). apply with no ecosystem argument infers python (uv), typescript (Biome, vitest) and bash from the repository, drafts each command surface from the bundled default specialized to the repo, and interviews before writing: with no user to answer, no .claude/ecosystems/*.yaml is written. nothing-written checks created files, uv-specialized the reply; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash Write Edit."
tags: [toolchain, setup, apply, interview, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply presents drafted command surfaces for python (with uv run, since api/uv.lock exists), typescript and bash, each with a recommendation, and asks before writing; no .claude/ecosystems/*.yaml file is created."
---

/toolchain:setup apply
