---
bump: minor
---

### Added

- A layout-stability concern for `/user-interface:design` and `/user-interface:audit`: reserved space for async content and media, equal-width digits on changing numbers, labels that swap without changing width, constant font weight on interaction, persisted state right on first paint, late banners that overlay rather than push, and long user text that cannot break the layout, with audit severities.

### Changed

- `/user-interface:write-css` now also triggers on "this page feels unfinished", "the numbers jump when they change" and "the page shifts as it loads", and its text-and-media recipes name the concern rules they implement.
