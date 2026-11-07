---
description: "setup check in a committed repository with no attribution config in any layer: all three layers absent is a valid state that yields the bundled defaults, not an error, and the read-only check writes no config. The prompt names check, the argument the router accepts (setup SKILL.md 47-50), instead of legacy setup 1's show. Needs --scaffold --allow-tools Bash."
tags: [attribution, setup, outcome, read-only, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "The reply reports the bundled defaults as the effective values because no layer exists, and treats that as a valid state, not an error. No shell write touches any attribution*.yaml or attribution*.json file. Asking which initial keys to set is fine."
---

/attribution:setup check
