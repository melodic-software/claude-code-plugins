---
description: "Value test, not for merge: does the team's design guidance change a call on duplicated code? Compare run, merge base (no guidance skill) against head (design-guidance skill). The grader checks the rule-of-one position in the reply."
tags: [engineering-concepts, guidance-value]
max_turns: 8
timeout_seconds: 300
expected_outcome: "The reply recommends extracting the helper now, at the second copy."
---

A teammate copied the same 15-line retry-with-backoff helper into two of our services this week. They say they'll extract it into a shared package if it shows up a third time. Should we extract it now or wait? Before you answer, use any design guidance our installed skills offer. Give a recommendation in under 200 words.
