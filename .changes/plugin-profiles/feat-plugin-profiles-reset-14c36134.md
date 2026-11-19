---
bump: minor
---

### Fixed

- The `/plugin-profile` picker's second write after a reload runs `apply --finish-pending`, which writes only while the folder's switch is still pending, so it never writes back a profile cleared or reset since.
