---
bump: patch
---

### Fixed

- The interview page now escapes every interpolated value in its HTML builders: the decision and state class names on the status chips, the revision number in the changed-since-confirmed line, and the source layer on the Settings rows no longer reach the markup raw. Audited all 31 `innerHTML` sites; the rest already passed through `esc()` or were constant markup.
