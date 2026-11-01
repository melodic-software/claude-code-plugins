---
bump: minor
---

### Added

- `/harness-ops:morning-brief precision` splits each lane's answered outcomes and precision by who wrote the answer (`bot`, `user-marked`, `user-unmarked`, `unknown`) under `by_author_kind`, beside the combined figures, and the markdown report adds a by-author table. The snapshot records each comment's raw `author_type` (the GraphQL author `__typename`); compute derives the kind from it and, for a user account, whether the answer has a D5 `<!-- d5 finding=` marker line. The snapshot schema is now 3. `bot` and `user-marked` precision is marked as an agent-labeled upper bound, and windows before the marker landed on 2026-11-01 show zero `user-marked` answers ([#11841](https://github.com/melodic-software/claude-code-plugins/issues/11841)).
