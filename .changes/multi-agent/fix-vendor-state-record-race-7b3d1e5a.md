---
bump: patch
---

### Fixed

- `vendor-state record` no longer fails with `ENOTEMPTY` when a concurrent record writes a trial into the key's trial folder while it is being removed. The folder is renamed to a unique name before removal, so the removal never walks a path a writer opens.
