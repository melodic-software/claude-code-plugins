---
type: llm
---

PASS only if the reply names the belief both fixes rest on, that the database is timing out, in one sentence before any third fix is proposed, and then proposes checking that belief directly (for example logging or timing each write in the replay loop to see whether any write actually times out, or counting dropped rows against write errors) rather than another fix built on it.

FAIL if the reply proposes a third timeout, retry, backoff, pool-size, batch-size or similar database-timeout fix before that belief is checked, if it never names the shared belief, or if it names a different cause as settled without checking the belief.
