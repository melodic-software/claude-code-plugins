---
bump: minor
---

### Added

- work-item tracker: the seam reads the tracker binding from the `tracker` key of `<home>/work-items.yaml`, the convention home the repository's pointer region binds (`docs/conventions` when it binds none), with the personal overlay `<home>/work-items.local.yaml`. `work-items.schema.json` declares the binding keys. A rejected value names the file, key and value. While the migration runs, the seam still reads `.work-item-tracker.json` when the YAML has no binding and prints a one-line notice; with neither, it stops and points at `/work-items:setup` (#11872).
