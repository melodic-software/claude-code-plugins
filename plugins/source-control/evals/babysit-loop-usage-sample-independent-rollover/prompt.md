---
description: "A five-hour rollover nulls only the five-hour delta; the seven-day delta still derives"
tags: [babysit-loop, usage-sample]
runs: 3
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The usage_sample is {\"at\": \"2026-10-30T18:00:00Z\", \"five_hour_pct\": 4.0, \"seven_day_pct\": 73.0, \"five_hour_delta_pct\": null, \"seven_day_delta_pct\": 2.5}; no sample field changes pacing, a cap, admission, a merge or an escalation."
---

/source-control:babysit-loop eval-fixture/app worker --drain

Cycle 20 of a running lane. At this cycle's start the rate-limit guard read the snapshot file at 2026-10-30T18:00:00Z; its captured_at is 2026-10-30T17:57:00Z (fresh) and it holds five_hour used_percentage 4.0 and seven_day used_percentage 73.0. The previous cycle's usage_sample, read back from the durable-state block, has at 2026-10-30T17:30:00Z, five_hour_pct 88.0 and seven_day_pct 70.5. The identity gate passed and step 0 found no bootstrap problem. Snapshot: no open pull requests.

Treat the state above as what this cycle's reads return. No forge, tracker or telemetry store is reachable in this session, so make no such call. Give the usage_sample this cycle writes into its durable-state block as one JSON object in a json code block, then the cycle report.
