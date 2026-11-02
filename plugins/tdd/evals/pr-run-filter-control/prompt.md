---
description: "Regression guard, likely null in both arms. The description's scope line: 'Not for HOW to run tests in the project (use the project's own test tooling and workflow for that).' SKILL.md Scope boundary repeats it: 'For running, filtering, or scaffolding tests, use your project's own test tooling.' A request for the dotnet test filter syntax is a near-miss on vocabulary (tests, xUnit) but asks how to run tests, so the run makes no tdd:principles call and answers with a --filter command. A model without the plugin passes too; this case guards against a description rewrite that makes principles fire on every test-related request. Paired hard cases: pr-interface-in-process and pr-precondition-significance. Read-only tools only; no grant needed."
tags: [tdd, principles, outcome, routing, regression-guard]
max_turns: 6
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run makes no Skill call to tdd:principles. The reply gives a dotnet test command with a --filter option."
---

Give me the exact dotnet test command that runs only the tests in the OrderServiceTests class of our xUnit project, nothing else.
