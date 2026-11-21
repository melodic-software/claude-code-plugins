---
bump: minor
---

### Added

- Every deepening candidate carries a required `size`: `S`, `M` or `L` with a basis of at most twelve words. The report shows it as a badge on each card, with its basis, and in each sidebar item, and the key defines each size the page uses. The report record moves to `schema_version` 2, and the builder refuses a candidate without a valid size, naming it.
