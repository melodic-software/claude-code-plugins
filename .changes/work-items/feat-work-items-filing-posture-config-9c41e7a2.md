---
bump: minor
---

### Added

- `filing_posture` (`manual-only`, the default, or `allowed`) is now a work-items key in
  `docs/conventions/work-items.yaml`, repository layer only: the team policy for a scanner's
  explicit filing argument such as `/bugs:scan --track`. It moved from the bugs plugin.
- An eval case for "no ticket when unsure": `track add` for an unreproduced signal that
  near-matches an open item files nothing and records it there as seen again.
