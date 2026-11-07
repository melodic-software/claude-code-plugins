---
bump: minor
---

### Added

- `loop.findings-after-first-review` (`blocking-only`, the default, or `all`): what a CI review lane reports on a head after the first one it reviewed whole. The schema declares it and resolve-config emits it with its default.

### Changed

- The `loop.review-rounds` default is 3, matching the design record's fix-round cap; it was 2. A repository that does not set the key now gets 3 full review rounds before the high-severity-only pass. This repository already sets 3.
