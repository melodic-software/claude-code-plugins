---
bump: patch
---

### Fixed

- The monthly wrapper template's help text links the permission-modes page's live auto mode anchor (`#eliminate-prompts-with-auto-mode`) instead of a heading-derived anchor that the page does not define. The wrapper's behavior is unchanged, but an installed copy no longer matches the template, so `/machine-health:setup check` reports it stale and offers the refresh.
