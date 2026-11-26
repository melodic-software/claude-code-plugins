---
bump: minor
---

### Added

- **`/session-flow:workflow` ships its stage map as data, `reference/stages.yaml`.** It holds the ladder in order, each stage's optional or conditional flag and entry skill, and the declared loop-backs and skips. The skill renders its overview from it, and a skill's own `## Next` bullet now wins over the ladder, which is the fallback when no bullet matches.
