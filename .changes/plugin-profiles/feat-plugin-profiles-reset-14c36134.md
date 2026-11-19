---
bump: minor
---

### Added

- `profiles.mjs reset` puts every settings file a profile changed on the machine back, user settings included, behind one preview and one yes; a reset stopped part way finishes on the next run.

### Changed

- A one-session file also names each installed plugin of every other marketplace some profile governs, at its value at launch, so a reset or another profile elsewhere never changes that session's plugins; a later `/plugin` toggle of such a plugin reaches only sessions started after it.

### Fixed

- The `/plugin-profile` picker's second write after a reload runs `apply --finish-pending`, which writes only while the folder's switch is still pending, so it never writes back a profile cleared or reset since.
