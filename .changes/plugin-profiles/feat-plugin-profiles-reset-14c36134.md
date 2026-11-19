---
bump: minor
---

### Added

- `profiles.mjs reset` puts every settings file a profile changed on the machine back, user settings included, behind one preview and one yes; a reset stopped part way finishes on the next run.

### Fixed

- The `/plugin-profile` picker's second write after a reload runs `apply --finish-pending`, which writes only while the folder's switch is still pending, so it never writes back a profile cleared or reset since.
