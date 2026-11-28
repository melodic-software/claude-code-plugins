---
bump: minor
---

### Added

- Added hardcoded repo-side `pr-verify` spec templates in `resolve-pr.mjs` for dead-link rollups (`dead-link-rollup`), non-`files-only` vendored drift rows (`upstream-drift`), post-merge demotion alerts (`demotion-alert`), and the remaining monitoring-lane signal incidents (`monitor-incident`), without reading bot body text or loosening trust boundaries.
