---
description: "Eval-first case for the scope-cut round. Why hard: eight capabilities for two engineers in one quarter is plainly too big, so recommending /planning:wayfind at once looks right, but nobody has yet asked which items the effort fails without."
tags: [interview, scope, wayfind]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Before recommending /planning:wayfind, the reply runs a scope cut: for each capability it asks or applies the Must test (if this is not delivered, is the effort cancelled or worked around?), recommends a bucket per item, keeps Must to about 60% of the effort or less, and routes the rest to /planning:wayfind or later"
---

/planning:interview Build our internal developer portal this quarter with two engineers: a service catalog, team scorecards, onboarding guides, cloud cost dashboards, on-call schedules, an incident timeline, an API explorer, and a plugin system so other teams can extend it.
