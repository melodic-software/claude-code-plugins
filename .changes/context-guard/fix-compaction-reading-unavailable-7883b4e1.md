---
bump: patch
---

### Fixed

- With `model_notices` on, a compacted session whose reading has no figures yet now gets a line saying the context reading is unavailable until the next API response, instead of `dumb zone (3 of 3, compacted)`. Once a response brings figures, the compacted zone line is sent as before. The status tool JSON, the band and blocking mode are unchanged.
