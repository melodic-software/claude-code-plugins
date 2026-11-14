---
bump: patch
---

### Fixed

- **`read-pre-ready.sh` fails closed on a `pre_ready` list holding an empty item or a key with no value.** The shared YAML parser emits no record for `why: []`, `note:` or a bare `-`, so such a list was honored; now every step runs and the report names the reason. The reader also keeps each item's fields in an array it creates fresh, so an inherited `item_<n>_step` or `item_<n>_enabled` in the environment can no longer fill a missing value.
