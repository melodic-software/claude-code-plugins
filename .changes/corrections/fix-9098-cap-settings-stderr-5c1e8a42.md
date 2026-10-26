---
bump: patch
---

### Fixed

- `scripts/codify-settings.mjs` and `scripts/findings-buffer.mjs` print at most the first five errors per settings layer, then `and N more`, so a committed `corrections.yaml` or `findings-buffer.yaml` full of unknown keys no longer floods stderr.
- `recurrence.min_occurrences` now has a maximum of 1000; a larger value is dropped with a note on stderr and the threshold falls back as for any invalid value.
