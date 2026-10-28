---
bump: minor
---

### Added

- `review-threads.reviewer-ids` lists review bots, besides `claude[bot]` and the review lanes, whose review threads pr-unblock's `address-feedback` works exactly as the reviewer bot's (owner decision 2026-10-26): the select job, the reply job's re-read, `fix-ci-context.mjs` and `pr-feedback-dispatch.yml` all keep such a thread, an `INCORRECT` reply on a non-CRITICAL one goes to the adjudicator (a listed bot's P0 or P1 severity badge counts as CRITICAL, so only its P2 and P3 findings are adjudicated, a finding whose badge does not read goes to a person, and one whose text names a security class goes to a person as a security question), and the trusted-person and human-gated rules apply unchanged. The list is matched on the account id GitHub records for each comment and its review, never a login; the bot's later comments count as the reviewer bot's, and anyone else's leaves the thread alone. This repository lists `chatgpt-codex-connector[bot]` (199175422). The resolved config carries the list as `review-threads`.
