---
bump: minor
---

### Added

- `/harness-ops:morning-brief precision` splits each lane's answered outcomes and precision by who wrote the answer (`person`, `agent`, `bot`, `unknown`) under `by_author`, beside the combined figures, and the markdown report adds a by-author table. The snapshot records each answer's `author_kind`, read from the GraphQL author `__typename` and, for a person's account, the D5 marker or Claude Code attribution line; the snapshot schema is now 3. Agent-labeled precision is marked as an upper bound ([#11841](https://github.com/melodic-software/claude-code-plugins/issues/11841)).
