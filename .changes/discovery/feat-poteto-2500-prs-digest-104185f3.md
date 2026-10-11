---
bump: minor
---

### Added

- **`explore_output` picks what `/discovery:explore` replies with.** `explain` replies with a
  walkthrough of how the scope works, each step citing `path:line`; `change-prep` replies with the
  handoff summary for the next stage. The default, `auto`, picks `explain` only when a person asks
  how something works and `change-prep` otherwise, including every call from another skill, so no
  calling skill changes; a caller can pass `--output explain`. `EXPLORE.md` is written the same
  way under every value. Set it per user in `userConfig` or per repository in
  `docs/conventions/discovery.yaml` (schema `schemas/discovery.schema.json`), which wins; the run
  names the layer that supplied it, and a value outside the three is reported with its file and
  key while the run uses `auto`. Keys: `reference/config.md`.
- **`/discovery:setup apply` writes `docs/conventions/discovery.yaml`.** It checks every value
  against `schemas/discovery.schema.json` and validates the whole file before writing, refuses an
  invalid value or key, writes nothing outside `docs/conventions/`, and prints the diff and waits
  for the operator's yes before changing a file that exists. `check` now also validates that file.

### Changed

- **`trace-intent` searches incident records for code that only matters when something fails.**
  For such a target, `context/evidence-categories.md` adds incident and follow-up tickets to the
  tracker search and postmortems to the long-form documents search, queried by error text and
  constant values as well as the symbol.

### Fixed

- **`/discovery:setup` runs the shared `lib/setup-apply.mjs`.** A key the schema does not list in `docs/conventions/discovery.yaml` is named in one warning and ignored: `--check` still prints the valid keys (exit 1), and `apply` writes beside it and keeps its line as written; such a key set twice or holding a map or list is still refused. `apply` and `--check` now refuse a root that is `$HOME` or an ancestor of it, a CRLF file is written back with CRLF (one mixing CRLF and LF is refused), and the shared parser now refuses a tab indent and an unquoted colon followed by a space in a value (`key: a: b`).
