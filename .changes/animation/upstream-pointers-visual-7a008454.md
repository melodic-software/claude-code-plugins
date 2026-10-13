---
bump: patch
---

### Changed

- **The image long-edge limit is read live, not restated.** The rotoscope method's review record keeps our rule (tile and crop so no image is downscaled) and points at the vision guide's resolution table with an anchor, an as-of date and a recheck trigger; `learn-style` routes to that record instead of repeating the figure, and `review.py` keeps the value in force.
