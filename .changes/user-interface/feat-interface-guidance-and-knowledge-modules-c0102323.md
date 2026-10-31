---
bump: minor
---

### Added

- `/user-interface:design` and `/user-interface:audit` gain web color guidance: oklch for new colors, contrast repaired by moving lightness only against the WCAG 2.2 AA bar with APCA as an advisory second check, every text pair checked in both themes, tonal scales with one fixed hue and per-hue chroma, dark-mode colors from a remap of the scale's roles, value-for-value conversion from hex, `rgb()` and `hsl()` with `none` as the hue of grays, gamut clamping with a Display P3 layer, a `--focus-ring` token held to 3:1 in both themes, and Tailwind `@theme` color tokens read only in Tailwind projects.
