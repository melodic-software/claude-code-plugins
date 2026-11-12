---
bump: patch
---

### Fixed

- babysit-prs's GitHub rate guard reports an HTTP 5xx whose only signal is a `Retry-After` header as `GitHub server error` ("GitHub answered HTTP 503 with a Retry-After; no GitHub call is sent before ..."), not as an exhausted rate-limit pool. The hold is unchanged: every pool, for the `Retry-After`, exit 75. A 5xx that also carries `x-ratelimit-remaining: 0`, a rate-limit or secondary-limit message or a GraphQL `RATE_LIMITED` error, and any 403 or 429, keep the rate-limit wording. Each stop's cause also goes in the job's `api-budget/cause` file beside the stop file, so a later process refused by the stop names a server error hold as one; a stop with no cause reads as a rate limit. The merge-queue ejection discount counts and forgives exactly the gate lines it did before, under their new wording.
