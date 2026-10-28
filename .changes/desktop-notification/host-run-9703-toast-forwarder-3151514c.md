---
bump: minor
---

### Added

- A hooks module forwards each toast a mod shows as a native notification through the plugin's
  bell, OSC 9 and OS toast channels, and the toast still shows (#9703). The new
  `desktop_notification_forward_toasts_enabled` option turns it off. Needs Claude Code 2.1.287 or
  later with mods on.
