---
description: "Asked what two scoped Bash denies saved, the audit says a scoped deny saves nothing, names the bare-name deny as the only priced one, and invents no figure"
tags: [context-budget, audit, outcome, scoped-deny]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says Bash(rm:*) and Bash(curl:*) save nothing (the Bash schema stays), that only a bare-name deny removes the schema and is priced, and states no nonzero token saving."
---

/context-budget:audit Last week I added `Bash(rm:*)` and `Bash(curl:*)` to `permissions.deny` in my project settings. How many startup tokens did those two rules save me?
