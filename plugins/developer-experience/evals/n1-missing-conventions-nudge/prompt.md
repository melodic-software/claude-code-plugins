---
description: "Scenario N1 (build-cli, missing-conventions nudge), the plan turn only. The bare tarnquill copy has no conventions file and no pointer line, so the reply tells the user to run /developer-experience:setup. The grader reads the final reply only: the source scorer read all of the turn's text, and the trace holds the skill body, which names the setup command itself. The source scenario runs the plugin arm only; read the WITH column, or pass --ablation none. A run needs --scaffold and --allow-tools Write Edit Bash; the source scenario grants Bash(dotnet:*), Bash(git:*), Bash(make:*) and Bash(bash scripts/*)"
tags: [build-cli, tarnquill]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "The final reply tells the user to run /developer-experience:setup because the conventions file is missing"
---

/developer-experience:build-cli Add an `env doctor` command to our team CLI that reports the .NET SDK version.
