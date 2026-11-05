---
bump: minor
---

### Changed

- `list-frontier --autonomous` reads each candidate's `Work status` field when `status-storage` reports `field`: a hold state in the field (`needs-human`, `needs-owner-decision`, `needs-reporter-info`, `needs-spec`) holds the item even when the labels do not, the labels decide everything else, and a failed read warns and falls back to labels. The new `get-statuses` verb reads the values; the GitHub adapter implements it.
