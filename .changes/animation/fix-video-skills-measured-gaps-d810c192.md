---
bump: minor
---

### Added

- **`render.py --shots shots.json`** compares the film with the shot list (fps, size, duration and frame count) and exits 1 on a mismatch, so a short render no longer exits 0. `produce.py review` runs the same comparison, which now includes the frame count.
- **A fresh-context review before delivery.** `/animation:produce` hands the rendered film to a reviewer that did not build it (`reference/independent-review.md`) and delivers only on its SHIP; it also says what to do after a failed pack check and never to add marks only to pass a row.

### Fixed

- **Capture waits for the scene to finish loading.** `render.html` exposes the scene import as `window.sceneReady` and `capture.mjs` waits on it, so a `DURATION` set after a top-level `await` is the one read.
- The skill documents `--root` for sharing modules and the shot-module contract (`drawShot(ctx, t)`).
- The `offstep` description in `inkstats.py` and the learn-style statistics reference now say what the code counts: a 2 then a 4 on 3s is one uncounted pair, and a lone 2 or 4 counts in both its pairs.
