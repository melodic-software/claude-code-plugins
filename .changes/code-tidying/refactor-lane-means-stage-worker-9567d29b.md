---
bump: major
---

### Changed

- **`/code-tidying:tidy` hunts focus areas, not lanes.** "Lane" now means only a worker that serves
  one pipeline stage, so the glob-scoped slice tidy rotates through is a focus area. Project focus
  areas live in `.claude/tidy-areas/<area>.md` (move any `.claude/tidy-lanes/` files there), the
  required section `## Lane-specific extra exclusions` is now `## Area-specific extra exclusions`,
  the bundled focus areas are under `skills/tidy/areas/`, and the templates are
  `templates/*-area.template.md`. `/code-tidying:setup` checks and scaffolds the new paths, and
  `batch-simplify` and `audit-dead-code` use the same word.
