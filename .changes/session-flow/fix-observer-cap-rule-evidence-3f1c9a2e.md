---
bump: patch
---

### Fixed

- A live check's `rule` or `evidence` longer than `observer_field_max` is now cut to that cap, ending in `…`, instead of failing the parse as `field_too_long:rule` or `field_too_long:evidence`; the check prompt now states the cap for both. A finding over the cap still counts as `parse_failed` with `field_too_long:finding`.
