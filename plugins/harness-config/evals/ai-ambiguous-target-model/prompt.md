---
description: "Hard. A family alias with no version aborts the run at invocation: SKILL.md Arguments, 'Fail loud on ambiguity: a value may carry no version at all, such as a family alias like opus ... aborting the run with an error that names the exact argument to pass (--target-model <version>) ... never a silent guess that a family alias means its newest version'; the suggested versioned token is offered for the user to confirm, 'never a value the run proceeds on'. The cost line calls it 'an invocation-time validation abort'. Hard because guessing the newest Opus and auditing anyway looks helpful. Source: the before SKILL.md contract. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, audit-instructions, outcome, fail-loud, scaffold]
runs: 3
max_turns: 15
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, Agent]
expected_outcome: "The reply stops and asks for --target-model with a versioned value (`<version>` or a token such as opus-5-5); neither pre-scan runs and no subagent is dispatched."
---

/harness-config:audit-instructions --target-model opus
