---
bump: patch
---

### Changed

- the shared config-cascade library gains `readLayers`

  It returns each layer's own accepted values, unmerged, for the shared
  medium resolver. `resolve()`, which this plugin calls, is unchanged.
