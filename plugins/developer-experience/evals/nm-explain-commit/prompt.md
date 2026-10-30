---
description: "Scenario NM-explain (near-miss stays quiet): explaining the team CLI's interactive commit command is close to tooling work but asks for no tool to be built or audited, so build-cli and audit-tools stay out of it and the workspace stays unchanged: no Write or Edit call, no Bash call that writes, moves or deletes a file, and no created file other than dotnet build output under obj/ or bin/. The source scenario scores it pass/fail in the plugin arm only; the baseline arm should pass too"
tags: [stays-quiet, near-miss, scenario]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "Explains what `tq commit` does from src/Tarnquill.Cli/Commands/CommitCommand.cs; makes no Write or Edit call, writes or deletes nothing through Bash, and creates no file; makes no Skill call to build-cli or audit-tools"
---

Explain what the interactive commit command does.
