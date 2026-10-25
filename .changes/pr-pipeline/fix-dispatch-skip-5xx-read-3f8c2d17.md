---
bump: patch
---

### Fixed

- The pr-unblock dispatcher no longer fails its run when GitHub answers one pull request's read with a 5xx. A GraphQL query answered 5xx is now sent again with the same bounded backoff and per-attempt timeout as a GET (`retryServerErrors`). A mutation is still sent once: a document that names a mutation or subscription anywhere, or a request that names an operation, is never resent. A per-PR read that still answers 5xx after those retries logs a warning naming the PR and skips that PR until a later run, in fix-docs, resolve-conflicts, review-dependency and fix-ci (its hold read and its required-run read). A rate limit or any other read error still fails the run.
