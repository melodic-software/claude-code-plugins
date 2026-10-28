---
bump: minor
---

### Added

- **`audit`, `realign` and `migrate` run `scripts/quote-check.sh` first** ([#9698](https://github.com/melodic-software/claude-code-plugins/issues/9698)). Each skill grants the script by its exact path with no `*`, so the grant covers the bare command only. Each run lists every `drift` result at the top of its output, with the record's section and both wordings, and names the wording a dependent proposal rests on. Each proposal quotes the deciding sentence of every docs record it relies on, and one that relies on an `unverified` or drifted record is labeled "unverified as of <date>". `audit` writes those records into a new `Mechanics` field of each finding, described in `context/findings-artifact.md`. `realign` presents them at its per-item gate and applies no finding whose record drifted until a re-audit. The audit's read-only rule now names the docs cache the check refreshes.

### Changed

- **`migrate` no longer grants `WebFetch`.** Its docs reads go through `scripts/fetch-docs.sh`, which takes a permission prompt per call, so the standing grant contradicted the skill's own rule that fetchers stay out of `allowed-tools`.
- **The README revisit trigger for the `Write`-triggered rule names its records**: MS-5 for the path-scoped rule, MS-2 for a nested `CLAUDE.md`, and the write-trigger gap in `context/verified-mechanics.md`.
