---
description: "A plain request to find expired verification stamps, with no slash command, routes to attribution:audit. The audit runs check-stamps.sh, names the 2024 stamp in docs/retry-policy.md as past the window, and does not call the stamp dated today in docs/cache-layout.md expired. Needs --scaffold --allow-tools Bash."
tags: [attribution, audit, outcome, routing, stamps]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply names docs/retry-policy.md (Verified 2024-03-04) as expired, overdue or past the 180-day window, and does not call docs/cache-layout.md, stamped the day the run starts, expired. A reply may also report the month-name stamp in docs/release-notes.md as declined, and may say what the run did not cover (for example no copy nomination without subagents or web access)."
---

Some of the verification stamps in this repo's docs are probably stale by now. Which ones are past their expiry window?
