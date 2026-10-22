---
bump: minor
---

### Added

- Finding mutes: a new `<StateBase>/state/mutes.json`, validated by `catalog/schemas/mutes.schema.json`, records list items the owner has marked as expected. Each item is named by a stable FindingKey; the orchestrator reads the file without creating or migrating anything and passes each list-style check its muted keys as a `-MutedKeys` argument, and a muted item stays listed but no longer counts toward the check's severity. `approvals.json` and its schema are unchanged. A downgraded plugin ignores mutes.json, so muted items raise severity again until the upgrade; nothing FAILs and nothing is stripped.

### Changed

- `approvals.json` is now read with `FileShare.ReadWrite | FileShare.Delete`, so a writer replacing the file no longer makes a run fall back to "nothing approved".
