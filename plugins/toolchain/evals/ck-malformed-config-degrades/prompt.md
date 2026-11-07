---
description: "Legacy check 6. A malformed tracked dotnet.yaml warns and degrades to inference (rung 2); the run goes on to a results report instead of a hard stop. Whatever inference resolves may meet a missing dotnet on this host, so any Overall verdict counts; only an abort does not. warns-malformed and overall-line read the reply; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, resolution-ladder, malformed-config, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply warns that .claude/ecosystems/dotnet.yaml is malformed, resolves dotnet's commands by inference from the repository instead, and still ends with a results table and an Overall line (PASS, FAIL or INCOMPLETE)."
---

/toolchain:check dotnet
