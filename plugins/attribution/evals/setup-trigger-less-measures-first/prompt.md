---
description: "setup asked to turn on the trigger-less stamp check in a docs tree whose three stamps include a month-name one: it measures first with check-stamps.sh --trigger-less, reads the declined share as the deciding evidence, and recommends from that measurement; bare setup is check (SKILL.md line 49), so no config is written. Needs --scaffold --allow-tools Bash."
tags: [attribution, setup, outcome, read-only, stamps, no-network]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "check-stamps.sh --trigger-less runs. The reply bases its recommendation on that run's declined share or flagged files, recommends leaving the check off with that reason or explains from the measurement why it could be enabled, and does not report the check as enabled. No shell write touches any attribution*.yaml or attribution*.json file."
---

/attribution:setup Turn on the trigger-less stamp check for this repository.
