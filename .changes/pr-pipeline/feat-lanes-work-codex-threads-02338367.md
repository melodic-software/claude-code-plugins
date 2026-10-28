---
bump: minor
---

### Added

- `review-threads.reviewer-ids` lists review bots, besides `claude[bot]` and the review lanes, whose review threads pr-unblock's `address-feedback` works exactly as the reviewer bot's (owner decision 2026-10-26): the select job, the reply job's re-read, `fix-ci-context.mjs` and `pr-feedback-dispatch.yml` all keep such a thread, a disputed one is adjudicated as a code-review lane finding is unless the security-review lane held the bot's reviewed head as CRITICAL, which sends it to a person (the bot's own severity badge decides nothing), and the trusted-person and human-gated rules apply unchanged. The list is matched on the account id GitHub records for each comment and its review, never a login; the bot's later comments count as the reviewer bot's, and anyone else's leaves the thread alone. This repository lists `chatgpt-codex-connector[bot]` (199175422). The resolved config carries the list as `review-threads`.
