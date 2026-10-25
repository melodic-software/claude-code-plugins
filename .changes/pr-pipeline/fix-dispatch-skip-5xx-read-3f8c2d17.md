---
bump: patch
---

### Fixed

- The pr-unblock dispatcher no longer fails its run when GitHub answers one pull request's read with a 5xx. A GraphQL query answered 5xx is now sent again with the same bounded backoff as a GET (`retryServerErrors`; a mutation is still sent once). A per-PR read that still answers 5xx after those retries logs a warning naming the PR and skips that PR until a later run, in fix-docs, resolve-conflicts, review-dependency and fix-ci. A rate limit or any other read error still fails the run.
