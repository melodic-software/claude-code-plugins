---
description: "Scenario S6: an inventory of tarnquill's scripts and tools, on the converged fixture, so the no-plugin arm keeps the conventions file and its pointer. Every tool in the key is still needed, and delete tools are granted so leaving the workspace untouched is a choice"
tags: [audit-tools]
max_turns: 60
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Write, Edit, Skill, "Bash(dotnet:*)", "Bash(git:*)", "Bash(make:*)", "Bash(bash scripts/*)", "Bash(rm:*)", "Bash(git rm:*)"]
expected_outcome: "Keeps build.sh and build.ps1 as a bash and pwsh pair, clean-outbox.sh, the Makefile, the tq CLI and tests/Tarnquill.Core.Checks, each verdict citing file evidence; changes no file"
---

What scripts and tools does this repo have, and which do we still need?
