---
bump: patch
---

### Fixed

- `/harness-ops:setup apply` no longer deletes the whole `harness-ops.yaml` or `harness-ops.local.yaml` when it cleans a migrated `morning_brief:` block. New retirement records `harness-ops-r004` and `harness-ops-r005` use the `block` kind, so the clean removes only that block and keeps `registry_dir`, `verification` and every other key; a file left with nothing else in it is removed. `harness-ops-r002` and `harness-ops-r003` are demoted to `report-only`, so setup no longer offers their whole-file clean, and their notes no longer say nothing reads the file ([#14251](https://github.com/melodic-software/claude-code-plugins/issues/14251)).
