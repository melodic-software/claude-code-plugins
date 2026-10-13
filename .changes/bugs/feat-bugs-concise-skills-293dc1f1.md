---
bump: minor
---

### Changed

- `write` and `scan` have shorter descriptions and bodies, and `setup` has a one-line description and a shorter body. Outcome eval cases and held-out trigger probes measured each change against the old text before it shipped.
- The `!` pre-computed commands in `write` and `scan` fall back to a notice when the consumer-gotchas script fails.

### Added

- Five outcome eval cases for `write` and two for `scan` under `evals/`, and frozen trigger-probe sets for `write` and `scan` under `probes/`.
