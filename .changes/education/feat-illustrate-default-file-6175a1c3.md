---
bump: minor
---

### Changed

- `/education:illustrate` delivers a local file by default: with no medium argument and no `rendered-views` layer setting `medium:`, the ladder is now `file`, then `terminal`, and publishes an artifact only when an argument or a layer asks for it. (#6175)
