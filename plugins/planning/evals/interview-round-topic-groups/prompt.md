---
description: "Round 2 of a webhook-sender interview whose ready questions span two topics, retry policy and failure alerting. Why hard: the round must name each question's topic in its title and keep every question in its full layout; the easy failures are topic headers over the questions, titles with no topic, or a closing summary table of the questions. The round header carries a Scope check: line."
tags: [interview, round-layout, topic-groups, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Round 2 asks the four decisions from Q4 on, each title naming its topic in parentheses (retries or alerting), with no topic headers, keeps each question in its layout, carries a Scope check: line in the round header, and ends with the closing probe and no summary table"
---

/planning:interview Add retries and failure alerting to our outbound webhook sender.

Round 1 is answered and the terms are agreed: Q1, the quality bar is production; Q2, webhooks are delivered at least once; Q3, receivers deduplicate on the `event_id` header the sender already sends.

These decisions are open, and none depends on another, so they are ready for round 2:

- how many delivery attempts the sender makes before giving up (today it makes one POST and retries nothing)
- the delay between attempts
- who is alerted when deliveries to one endpoint keep failing (the on-call rota is in PagerDuty, and the team also has a #webhooks Slack channel)
- what an alert message includes (the endpoint, its last response status, how many events are waiting)

Ask round 2 now, then stop for my answers.
