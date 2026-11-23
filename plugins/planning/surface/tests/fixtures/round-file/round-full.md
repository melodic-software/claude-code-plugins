**Round 3.** The retry budget is three tries, and a failed retry pages no one.
Scope check: 9 of 27 questions registered; round 2 added 4, settled 3; round 1 added 3, settled 3
Later: alert routing, the on-call rota
Held: Q12 (queue choice) until the queue lookup returns

❓ Q10: **Should a failed retry write to the audit log?**

Context:
- Each retry runs in its own worker (`src/retry.ts:12`).
- Q4: you chose one write per job in round 1.
- The audit log takes one write per job today ([audit guide](https://example.com/audit)).

Source: [Audit log guide, Writes](https://example.com/audit#writes)
> One write per job. Extra writes are batched and may be dropped under load.
> Batches flush every five seconds.

➡️ My recommendation: **yes, one entry per failed retry**. The log already takes one write per job, so a retry entry fits it (verified, `src/retry.ts:12`).
Origin: drafted by the recommender from the audit guide
Basis: verified, `src/retry.ts:12` and the audit guide's Writes section
Checked against: the no-new-store constraint
Second view: write only the final failure, to keep the log short.
Departs from: Q4 (one write per job) because a retry adds a second write to a failed job.
Flips if: the audit log starts dropping batched writes in production.
Commits you to:
- one log entry per failed retry
- keeping the retry count in the entry

Alternatives:
- (a) Log only the final failure.
  The log stays short, but the retry history is lost.
- (b) Log nothing for retries.

---

❓ Q11: **Who reads the retry entries?**

Context:
- No reader is named yet.
- The draft entry shape:
````text
Q9: a fenced line, not a question
```
Basis: a fenced line, not a label
````

Discovery: who reads the entries settles whether they need a dashboard.

---

❓ Q13: **Which store holds the entries?**

Context:
- The store depends on the queue lookup.

Withheld: the queue lookup has not returned, so no store can be recommended yet.
Flips if: the lookup finds the queue already persists jobs.

You can answer in any order. Is there something else that would change these recommendations?
