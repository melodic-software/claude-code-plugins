---
bump: minor
---

### Added

- Two on/off settings, `session_start_profile_enabled` and `plugin_profile_module_enabled`, both on by default, turn off the SessionStart profile notice and the `/plugin-profile` mod on their own. Your value wins when set; otherwise the same key in the repository's `docs/conventions/plugin-profiles.yaml` decides. Both resolve through the shared hook-enablement helper, and `schemas/plugin-profiles.schema.json` checks the repository file.
