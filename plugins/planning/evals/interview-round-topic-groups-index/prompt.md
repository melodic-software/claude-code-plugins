---
description: "Round 2 of a webhook-sender interview whose frontier spans two topics, retry policy and failure alerting. Why hard: the round must keep every question in its full layout and also add topic headers and a closing index; the easy failures are one flat numbered list, or an index table that stands in for the questions."
tags: [interview, round-layout, topic-groups]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 2 asks the five decisions from Q4 on under at least two topic headers (retries and alerting), keeps each question in its full layout, and ends with one index table (Q, Recommendation, Basis, Main alternative), one row per question, before the closing probe"
---

/planning:interview me Add retries and failure alerting to our outbound webhook sender.

Round 1 is answered and the terms are agreed: Q1, the quality bar is production; Q2, webhooks are delivered at least once; Q3, receivers deduplicate on the `event_id` header the sender already sends.

These decisions are open, and none depends on another, so they are round 2's frontier:

- how many delivery attempts the sender makes before giving up (today it makes one POST and retries nothing)
- the delay between attempts
- what happens to an event after its last failed attempt
- who is alerted when deliveries to one endpoint keep failing (the on-call rota is in PagerDuty, and the team also has a #webhooks Slack channel)
- what an alert message includes (the endpoint, its last response status, how many events are waiting)

Ask round 2 now, then stop for my answers.
