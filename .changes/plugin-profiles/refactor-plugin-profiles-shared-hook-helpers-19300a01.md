---
bump: patch
---

### Changed

- Resolve `session_start_profile_enabled` in-process through the shared `lib/hook-enabled.mjs` helper and `plugin_profile_module_enabled` in-process through the shared `hooks/mod-hook-enabled.ts` helper, removing the per-plugin `lib/hook-enablement.mjs` bash wrapper and vendored `hooks/hook-enabled.sh` copy.
