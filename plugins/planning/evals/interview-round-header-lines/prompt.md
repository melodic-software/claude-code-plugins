---
description: "The round header: round 3 of a webhook-sender interview has six ready questions, one more held for a lookup and one topic not ready yet, so its header carries every line it can hold. Why hard: the old header restated the decisions so far and named held questions by id, so the easy failures are a recap of rounds 1 and 2 at the top, a Held: line, all six questions asked past the cap of 4, or the lines in another order."
tags: [interview, round-header, round-layout, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Round 3's header carries, in order, the Scope check: line in its 'N questions asked so far' form, an Open: line naming the who-is-alerted question in plain words with the PagerDuty lookup it waits on, a Next round (over the cap of 4): line naming the two ready topics the cap leaves out, and a Later: line naming the replay screen; it restates no earlier decision and has no Held: or Settled by evidence: line"
---

/planning:interview resume the webhook-retries interview; its ledger is `.work/webhook-retries/interview-checklist.md`, and rounds 1 and 2 are saved beside it.

[Session state: rounds 1 and 2 are answered and recorded. Six decisions are ready, and none depends on another: how long dead-letter rows are kept, who may replay a dead-lettered event, what an alert message includes, whether a 4xx response is retried, the timeout for one delivery attempt, and whether a replay writes an audit-log entry. A seventh, who is alerted when one endpoint keeps failing, waits on a lookup running in another session that checks whether our PagerDuty account has the Events API enabled; it reports back tomorrow. The layout of the replay screen is not ready to ask: it rests on who may replay. Write round 3, then stop for my answers.]
