---
bump: patch
---

### Fixed

- Lane scripts no longer fail an activity on one transient network error (undici `fetch failed`, `ECONNRESET`, `UND_ERR_SOCKET`). The shared client (`check-trusted-trigger.mjs` `retryServerErrors`) now times and resends a GraphQL POST whose document is a query, with no mutation, under its GET retry rules; a mutation is still sent once.
- `apply-patch.mjs`, `address-feedback.mjs` (publish-feedback, apply-dependency-verdict, verify-notes), `report-outcome.mjs` and `post-statuses.mjs` send a read, a GraphQL query, or a write that repeats to the same state again after a network error or a 5xx: at most 3 attempts, with a full-jitter wait of a random share of 4 s, then 8 s. The writes resent are the Git Data blob, tree and commit creates, a ref update, a pull request close, an issue label add or remove, and a commit status. After a `POST /pulls` that fails on the network, `report-outcome` reads the open pull request back and creates it again only when there is none. A comment, an issue, a ref create and any mutation are sent once. The wrapper is `retry-fetch.mjs`, one identical copy in each script directory, since each script runs from a copy of its own directory.
- `pr-unblock/dispatch.mjs` sends `Connection: close` on every request, so its workflow dispatch, which follows up to 5 x 10 s of waiting, goes out on a new connection rather than a pooled one GitHub may have dropped while it sat idle.
