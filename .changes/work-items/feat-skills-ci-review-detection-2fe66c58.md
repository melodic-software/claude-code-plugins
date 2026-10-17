---
bump: minor
---

### Changed

- **The `work` CI mode skips its pre-PR review when the CI code-review lane covers the repository.** When the runner writes a `review-venue.txt` whose `code-review` line reads `ci`, the run records `review` as `skipped` and notes the line in `not_done`; with no file, or a `local` line, it reviews its diff as before, as the stand-in for the CI lane.
