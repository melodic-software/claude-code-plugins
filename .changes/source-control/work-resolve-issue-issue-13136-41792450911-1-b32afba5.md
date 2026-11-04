---
bump: minor
---

### Added

- A `review_venue` setting (`auto`, `local`, `ci`, `both`; default `auto`) in `docs/conventions/source-control.yaml` and as a `userConfig` option, the repository value winning. `auto` keeps the per-lane CI health read; `local` runs every local review step; `ci` skips the local review steps and leaves the review to the CI lanes; `both` runs the local steps and still counts the CI lanes. The new `read-review-venue.sh` resolves it, reading the repository value at the pull request's base branch and honoring it only when that base is the default branch. An unknown value falls back to `auto` with a notice.
