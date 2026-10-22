---
bump: patch
---

### Fixed

- Lane scripts send a GitHub REST GET again when it is answered 5xx, answered 200 with an empty or unparsable body, or fails on the network, after about 2, 4 and 8 seconds with jitter, instead of failing the step on the first bad answer. Each attempt is aborted after 20 seconds, and the time failed attempts take plus the waits is capped at 60 seconds per API client. POSTs, 4xx answers, rate limits and other thrown errors are not retried here, and a retry line never prints an error's message.
- pr-verify, the feedback dispatcher and the workflow_run trigger gate read a commit's pull requests through GraphQL's `associatedPullRequests` when `GET /commits/{sha}/pulls` still fails after those retries, and apply the same open, same-repository and base filters to the result.
