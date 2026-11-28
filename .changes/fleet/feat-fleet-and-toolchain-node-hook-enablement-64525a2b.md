---
bump: minor
---

### Added

- Add the `peer_list_enabled` hook-enablement setting (default `false`) in `plugin.json`, `schemas/fleet.schema.json`, and `hooks/peer-list.mjs` via the shared in-process `lib/hook-enabled.mjs` helper so the SessionStart peer-list hook is opt-in and configurable per user or per repository.
