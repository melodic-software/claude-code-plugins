---
bump: minor
---

### Added

- `/docs-hygiene:audit-derivability` runs the spot test for a launch-loaded file (root `CLAUDE.md`,
  `AGENTS.md`, an unscoped rule) on the new `docs-hygiene:derivability-spot-tester` agent, which
  sets `omitClaudeMd` and reads the repository with Read, Grep and Glob only. `Explore` or `Plan`
  remain the fallback when that agent does not resolve.
