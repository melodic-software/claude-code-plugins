---
description: "Legacy code that cannot be put in a test harness. characterization-testing.md, 'When the Code Cannot Be Put in a Test Harness': make only the dependency-breaking change, then characterize, then refactor. The user wants to clean up a function that reads the clock and opens a database connection inside itself and has no tests. A model without the skill tends to say either 'write characterization tests first' (impossible as stated) or 'refactor it into a testable shape' in one step. Read-only tools only; no grant needed."
tags: [tdd, principles, outcome, routing, legacy-code]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the tdd:principles skill. The reply gives an order: first only the dependency-breaking change that lets a test reach the code, with no other cleanup in that step; then characterization tests of the current behavior; then the refactoring."
---

We have a 600-line `closeBillingPeriod` function with no tests. It reads the system clock and opens its own database connection in the middle of the function, so I can't call it from a test at all. I want to remove the duplicated proration code and rename its confusing parameters. I know the rule is to write characterization tests before changing legacy code, but I can't get it under test as it stands. What order should I do things in?
