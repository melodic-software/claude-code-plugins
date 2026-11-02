---
bump: patch
---

### Changed

- Lane scripts follow element 1 of the outage posture: each API call gets at most 3 attempts. The shared retry under `createGitHub` and `budgetedFetch` (`retryServerErrors` in check-trusted-trigger.mjs) resends a failed read twice, not three times, after a full-jitter wait (a random share of 2 s, then of 4 s), where they used to wait at least half of each step. enable-auto-merge's `withRetry` resends only a GraphQL mutation and leaves a query to the client's own retry, so a query goes out at most 3 times instead of 12.
- `retry-fetch.mjs` (apply-patch, pr-unblock and work-resolve-issue) resends a read refused on a rate limit, within the same 3 attempts, after the wait GitHub asks for: `retry-after`'s seconds, else the `x-ratelimit-reset` time when `x-ratelimit-remaining` is 0, else 60 s for a secondary limit. Those waits stay within 60 s per client. A longer wait is not taken, and the answer goes back as a failed read. A write the caller did not mark `safeToResend` is returned at once, and a fetch the rate guard already wraps (`budgetedFetch`, or the latch's `guard`) is left to the guard.
- pr-unblock's `report-escalation.sh` posts its escalation and lane-stopped comments once instead of up to three times, since a comment POST is not idempotent. When the POST fails, the job fails with the label on, and the next run posts the explanation.
