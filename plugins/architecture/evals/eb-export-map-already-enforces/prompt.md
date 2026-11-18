---
description: "A JavaScript workspace whose billing package.json exports only its root, with a recorded rule that other packages import billing by its root specifier only: the export map already enforces the rule, so the run adds no import scan, lint rule or other second check, proves the resolver refuses an injected subpath import and passes once it is removed, and records the enforcing command. Needs --scaffold and --allow-tools Bash Write Edit."
tags: [architecture, enforce-boundaries, outcome, scaffold, no-network]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "No script, lint rule, test or config is added for the billing rule, and no file outside a package source file and the topic doc is written. A subpath import of @shop/billing injected in reporting makes the check fail with the resolver's not-exported error, and the check passes after the injection is removed. packages/reporting/src/report.js holds no subpath import. The billing entry in the topic doc's Boundary rules gains the command that enforces it."
---

/architecture:enforce-boundaries Enforce our recorded boundary rule. You have my yes to inject and remove a test violation and to record the enforcing command. Add no dependency.
