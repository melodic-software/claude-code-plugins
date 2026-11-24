---
bump: minor
---

### Added

- `pull-request ready` runs `/verification:confirm` (if enabled) on the head when the body lists acceptance criteria and the diff is not docs-only, so each criterion names the test or check that proves it or reads `Not tested: <why>`. A criterion with neither is fixed or reported; the check never holds the flip.
- `pull-request prep` lists each test or assertion the diff deletes, skips or widens; each is restored or named with its reason under a `## Loosened checks` section, which `create` adds to the pull request body. Advisory only.
