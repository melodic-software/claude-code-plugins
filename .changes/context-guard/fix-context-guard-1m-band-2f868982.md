---
bump: minor
---

### Changed

- **The 1M-window token band reads `dumb` past 500000 tokens, not 250000 ([#6644](https://github.com/melodic-software/claude-code-plugins/issues/6644)).** At 26% of a 1M window the shipped bands read `dumb (3 of 3)` and sessions stopped work on it. The `smart` edge stays at 128000. The reader contract records the new basis: Google's GraphWalks BFS figures for Opus 5.5 and Fable 5.1, and Context Arena's 8-needle MRCR, where both Claude rows first score under one half at 512K. The 200k row and the percentage bands are unchanged; `zones.json` still overrides.

### Fixed

- **Band provenance figures.** The reader contract gave Claude Sonnet 5's 8-needle MRCR as at least 0.957 through 256K; the live table reads 0.529 at 128K and 0.522 at 256K. It also said no per-length data exists for Opus 5.5, but Google publishes its GraphWalks BFS scores (90.6% up to 128K, 66.8% from 256K to 1M).
