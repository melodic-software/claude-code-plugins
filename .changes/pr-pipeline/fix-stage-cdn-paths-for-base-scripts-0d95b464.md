---
bump: patch
---

### Fixed

- `collect-base-activity` stages `.github/scripts/apply-patch/cdn-paths.mjs` beside a script activity's base copy, so pr-unblock's `apply-dependency-verdict` and the `cdn-pins-sync.mjs` module `review-dependency.mjs` imports load again instead of failing with `ERR_MODULE_NOT_FOUND` on every Dependabot pull request.
