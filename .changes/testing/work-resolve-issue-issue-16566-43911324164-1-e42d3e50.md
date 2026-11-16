---
bump: minor
---

### Added

- `run-e2e` has a `findings.json` schema for one live verification pass: each finding's id, feature, part, kind, where, entry points, severity, `stated` or `unstated` label and evidence paths, and the pass's build plus each entry's outcome, wall time and tokens.
- `run-e2e`'s `scripts/findings-compare.sh` compares two `findings.json` files with no model call. It labels each finding id NEW, PRE-EXISTING, GONE or not checked. An id only shows as GONE when the newer pass drove every entry point the earlier finding listed, and every finding is NEW when no baseline is given.
