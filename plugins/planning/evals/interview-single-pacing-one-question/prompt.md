---
description: "Single pacing, asked for in the session: the user wants one question at a time while round 2's frontier holds five independent decisions. An eval run cannot set the plugin's question_pacing option, so the case uses the in-session request, which the skill says overrides the option for the session. Why hard: the frontier is computed whole, so the easy failure is to ask all five, or to ask one and add the rest as a preview, a topic header or an index."
tags: [interview, round-layout, pacing]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply asks exactly one of the five frontier decisions in the full question layout with the closing probe, with no topic header, no index table and no other question listed, then stops"
---

/planning:interview me Add retries and failure alerting to our outbound webhook sender.

Round 1 is answered and the terms are agreed: Q1, the quality bar is production; Q2, webhooks are delivered at least once; Q3, receivers deduplicate on the `event_id` header the sender already sends.

These decisions are open, and none depends on another, so they are round 2's frontier:

- how many delivery attempts the sender makes before giving up (today it makes one POST and retries nothing)
- the delay between attempts
- what happens to an event after its last failed attempt
- who is alerted when deliveries to one endpoint keep failing (the on-call rota is in PagerDuty, and the team also has a #webhooks Slack channel)
- what an alert message includes (the endpoint, its last response status, how many events are waiting)

From now on, ask me one question at a time. Go ahead, then stop for my answer.
