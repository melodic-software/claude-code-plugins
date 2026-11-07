---
description: "Legacy check 4. `/toolchain:check all` runs only the seven covered ecosystems: with tracked yaml and cross-cutting configs present and a workflow YAML changed, neither lint-only surface runs. The covered bash and markdown configs run; dotnet, python, typescript, powershell and go are disabled (`enabled: false`) so the run does not depend on host tools. lint-only-not-run and covered-ran read .calls.log; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, scope, scaffold, no-network]
max_turns: 35
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The bash and markdown lint commands run; the yaml and cross-cutting commands never run, even though their tracked configs exist and the workflow YAML and README changed."
---

/toolchain:check all
