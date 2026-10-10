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
