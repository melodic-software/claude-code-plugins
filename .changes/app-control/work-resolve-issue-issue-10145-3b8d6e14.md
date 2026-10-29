---
bump: patch
---

### Fixed

- A control skill's Ready command must now fail when the instance is unfit. The contract's new "The Ready command" section and `/app-control:map`'s Generate step require each check in Ready to exit non-zero when it fails, so a listing such as `docker ps` ends in `grep -q` on the expected row instead of passing with no rows. Map's proof runs Ready once more with the app stopped and records that it exits non-zero, read from the new `ready.exit` field of `/app-control:drive`'s report. `/app-control:map check` reports a `ready-listing` finding for a Ready command whose last stage is a bare listing, and create fixes each one before its proof.
