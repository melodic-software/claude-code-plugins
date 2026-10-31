---
bump: patch
---

### Fixed

- `/user-interface:design` now applies the routing-as-data 2.0.0 team-row limits. A team `routing.rows` entry is dropped when its id matches neither a bundled row nor its own installed plugin or skill, when it adds a `kind: tool` row, or when it reuses a bundled id but changes that row's `kind`, `detect` or `account`. When the installed list cannot be read, a row whose id matches no bundled row is also dropped. `scripts/detect.mjs --config` names each dropped row and the rule it broke in `routing_notes`. `reference/team.schema.json` states the three rules.
