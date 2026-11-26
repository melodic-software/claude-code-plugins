---
description: "Round 3 of a webhook-alerting interview with two open decisions, one of which rests on a lookup that runs in another session and reports back tomorrow, so it cannot return inside this run. Why hard: the easy moves are to ask both questions now, recommending a channel the lookup may rule out, or to wait and ask nothing; the skill names the dependent question in plain words on the round header's Open: line and asks the other."
tags: [interview, lookups, held, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Round 3 names the who-is-alerted question in plain words on its Open: line until the PagerDuty lookup returns and does not ask it, and asks the question about what an alert message includes"
---

/planning:interview Add retries and failure alerting to our outbound webhook sender.

Rounds 1 and 2 are answered: Q1, the problem is that failed deliveries are lost and nobody hears about them; Q2, the users are the receiving teams and our on-call engineers; Q3, the quality bar is production; Q4 to Q7 settled five attempts with exponential backoff from 30 seconds, a dead-letter table after the last attempt, and receivers deduplicating on `event_id`.

Two decisions are open: who is alerted when deliveries to one endpoint keep failing, and what an alert message includes (the endpoint, its last response status, how many events are waiting).

A lookup I started in another session is checking whether our PagerDuty account has the Events API enabled; it reports back tomorrow, and the answer decides whether alerts can page on-call or must go to the #webhooks Slack channel.

Ask round 3 now, then stop for my answers.
