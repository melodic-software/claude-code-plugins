---
description: "Legacy check 3. The tracked .claude/ecosystems/dotnet.yaml is rung 1 and authoritative: its project-specific test-cmd runs (it logs `dotnet test` to .calls.log through tools/run.sh), and the bundled `dotnet test` / `dotnet build` never run. ran-consumer-test reads .calls.log, no-bundled-dotnet the Bash calls; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, resolution-ladder, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The dotnet build, test and lint commands are the ones the tracked dotnet.yaml declares (bash tools/run.sh ...); no bare dotnet build or dotnet test command runs."
---

/toolchain:check dotnet
