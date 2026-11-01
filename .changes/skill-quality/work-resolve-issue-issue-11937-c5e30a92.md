---
bump: patch
---

### Added

- `measure-invocation.sh validate` prints a WARN for each probe competitor whose id is not from the probe file's own plugin. Probe sets should list same-plugin competitors only, so that a rewrite in another plugin cannot move a probe's score. The WARN never fails `validate`.
