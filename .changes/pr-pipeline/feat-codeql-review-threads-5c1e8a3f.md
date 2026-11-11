---
bump: minor
---

### Added

- `review-threads.reviewer-ids` lists `github-advanced-security[bot]` (62310815), so `address-feedback` fixes or settles, replies to and resolves code scanning (CodeQL) alert threads as it does the reviewer bot's (owner decision Q29). That bot cannot be summoned by a comment, so its threads need no `@codex` request: `requestSkip` works one when a trusted person or the lanes App opened the pull request (`UNSUMMONED_REVIEWER_IDS` in `address-feedback.mjs`), and logs `codex-request-untrusted` or, on unreadable triggers, `codex-request-not-found` otherwise. Resolving a thread does not dismiss its code scanning alert; the next analysis closes a fixed one.
