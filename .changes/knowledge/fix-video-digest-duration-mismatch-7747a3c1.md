---
bump: minor
---

### Added

- `video-digest watch` records a metadata versus probed duration mismatch. When the source metadata duration and the probed media duration differ by more than the larger of 5 s and 1% of the longer one, `watch.json` carries `durationMismatch` with both values and the slice `README.md` gets a `Duration mismatch` section. Agreement within that threshold records nothing, and the pipeline still uses the probed duration.
