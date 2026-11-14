---
bump: minor
---

### Added

- **A `prep_audits` list in `docs/conventions/source-control.yaml` sets the audit `/source-control:pull-request prep` runs for each change class.** Each `{class, enabled, skill}` item turns the `markdown`, `renames`, `skills`, `rules` or `tests` audit off (`enabled: false`) or, except for `tests`, replaces it with a named skill that receives the class's changed files. It is read at the default branch, never the working tree, through `scripts/read-prep-audits.sh`, and a missing key, another base branch or a list the reader cannot trust runs every default audit. The comment pass and `security` are not configurable here.
