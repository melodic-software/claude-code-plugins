---
bump: minor
---

### Added

- `/session-flow:orient`, `/session-flow:continue-in-background` and `/session-flow:audit-sessions` take an optional leading `unattended` argument. With it, the run records its native suggestion (`/recap`; `/background`, `/fork` or `/subtask`; `/insights`) in its output instead of asking; without it, the run asks. The argument hints list it.

### Changed

- `/session-flow:audit-sessions`'s argument hint shortens its action set to `[sweep|now…]` to stay within the 100-character budget; the Arguments line gives the full set.
