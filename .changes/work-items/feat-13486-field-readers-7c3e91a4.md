---
bump: minor
---

### Changed

- `list-frontier --autonomous` fails closed when the `Work status` field cannot be read: a failed `status-storage` or `get-statuses` read exits with the adapter's code and prints no envelope, and an answer without a `statuses` object exits `1`. It no longer falls back to labels.
