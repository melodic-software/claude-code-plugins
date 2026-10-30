---
bump: minor
---

### Added

- `work-item-tracker.sh status-storage [--repo <owner>/<repo>]` reports where the tracker stores an item's status: `field` when the organization has a `Work status` single-select issue field with options, else `labels`. The core reads it from the adapter's `get-field-options`. It reports `labels` for an adapter without that verb, such as `local-markdown`. It also reports `labels` when GitHub refuses the issue-field listing, as it does for a user-owned repository or a token without `read:org`. `CONTRACT.md` documents the output, and the tracker and conformance suites cover it.
