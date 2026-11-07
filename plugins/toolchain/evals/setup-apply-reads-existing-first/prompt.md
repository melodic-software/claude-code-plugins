---
description: "Legacy setup 2, run as `apply` (bare `/toolchain:setup` is now the read-only check). With tracked dotnet.yaml and python.yaml from an earlier run, apply reads both first, summarizes each current command surface, and proposes changes against that baseline; nothing is overwritten or dropped without the user confirming. summarizes-filters reads the reply; dotnet-kept and python-kept read the two files after the run; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash Write Edit."
tags: [toolchain, setup, apply, idempotent, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply summarizes both existing files, naming their project-specific test filters (Category!=Slow and not integration), and proposes changes against them; both files still hold those test-cmd values after the run."
---

/toolchain:setup apply
