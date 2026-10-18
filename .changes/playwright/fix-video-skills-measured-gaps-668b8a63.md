---
bump: minor
---

### Changed

- **`/playwright:demo-video` gives an outcome time to be read.** A hold that shows a step's `outcome` lasts its reading time (`captions.seconds_per_word`, never under `captions.min_seconds`, both new in `scripts/defaults.json`), and `quality_control.py` lets a still run in that hold take the reading time on top of `still_max`; holds with no outcome keep the limit. A step that stays on its page now shows its `outcome` too.

### Fixed

- A refused edit plan now names the steps whose shot search found no zoom shot, the usual cause behind a caption with no empty anchor.
- The camera-off `SKIP` in quality control no longer says "plain style" for a produced video.
- The skill covers looping CSS animations (including `::before` and `::after`) that keep `demo.settle` from finishing, and says where exploration artifacts and changed app state go.
