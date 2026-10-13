---
bump: minor
---

### Added

- `/bugs:scan` Lens 5, display formatting and fallbacks: dispatched when the scope renders user-facing data, it hunts values rendered wrongly for real input (hardcoded plurals, naive initials, images with no fallback, raw or unformatted numbers and nulls, truncation with no full value, leftover placeholders, fixed date formats). The shared excluded-classes rule now says a wrongly rendered value is not a formatting opinion, so the verification gate keeps such findings. The large-scope and top-effort lens counts go to 5.
