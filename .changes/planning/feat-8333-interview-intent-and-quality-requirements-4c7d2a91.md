---
bump: minor
---

### Added

- `/planning:interview`: in an engineering session the interview reads the consumer's standards before any bundled default, asks the intent question (is a second variant known, a category, or speculative; what the existing structure does; what upstream context says), and prompts quality requirements (NFRs) from a new prompt list, each scaled by the quality bar. The Brief records `Quality bar:` and `Intent:` lines under Captured assumptions, each quality requirement as a `Quality requirement:` line under Constraints, and `Overrides bundled default <principle> per <standards file>` when a consumer standard wins. Unattended, only the user's own words settle the intent question; otherwise it is recorded `blocked`, arbiter USER-RESERVED, and the Brief is still written. Upstream context is recorded as a short summary, with private titles and URLs left out of public or unknown-visibility repositories.
