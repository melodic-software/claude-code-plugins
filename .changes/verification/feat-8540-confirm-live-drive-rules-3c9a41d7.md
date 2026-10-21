---
bump: minor
---

### Added

- `/verification:confirm` gains three rules for the live drive, ported from cursor/plugins#573: ready means usable from an empty data directory (a port answering or a passing health check is not enough), a user journey is never weakened to make it pass (a missing seed-data precondition is reported as a failed journey with that reason), and a proof run on a stand-in lists every setup step the stand-in did that the target will not and marks those unverified. The outcome report gains a `Stand-in` line, and the skill states that its proof is tests and observed behavior, not model checking or proof. Two eval cases cover the journey and stand-in rules.
