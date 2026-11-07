---
bump: minor
---

### Changed

- `list-frontier --autonomous` fails closed when the `Work status` field cannot be read: a failed `status-storage` or `get-statuses` read exits with the adapter's code and prints no envelope, and an answer without a `statuses` object exits `1`. It no longer falls back to labels.

### Added

- The GitHub `get-field-options` output carries `field_id`, the matched field's numeric id (the id `set-fields` takes), or `null` when the organization has no such field.
