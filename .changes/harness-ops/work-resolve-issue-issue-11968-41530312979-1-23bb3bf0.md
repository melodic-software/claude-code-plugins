---
bump: major
---

### Removed

- `schemas/harness-ops.schema.json` is gone. The only keys it described, `morning_brief`, moved to the work-items plugin together with `/work-items:morning-brief`. The brief no longer reads `harness-ops.yaml` or `harness-ops.local.yaml`: move their `morning_brief:` block into `work-items.yaml` or `work-items.local.yaml` in the same convention home.

### Added

- Retirement records `harness-ops-r002` and `harness-ops-r003`. When `docs/conventions/harness-ops.yaml` or `docs/conventions/harness-ops.local.yaml` still holds a `morning_brief:` block, `/harness-ops:setup check` reports it as FAIL. `apply` then offers to move the block to `work-items.yaml` or `work-items.local.yaml`, and cleans the old file once you confirm the move.
