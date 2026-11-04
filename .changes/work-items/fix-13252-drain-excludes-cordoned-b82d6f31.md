---
bump: minor
---

### Added

- The tracker seam's normalized item object carries an additive `milestone` field: the milestone title on the GitHub adapter (`get-item` and `list-items`, GraphQL and REST reads), `null` on local-markdown and the gitea, jira and linear seeds.

### Changed

- `/work-items:work-loop` no longer lets an item in a cordoned milestone hold a `--drain` exit, reading the row's `milestone` and the names from `cordoned-milestones` in the target's `admission-rules.json`.
