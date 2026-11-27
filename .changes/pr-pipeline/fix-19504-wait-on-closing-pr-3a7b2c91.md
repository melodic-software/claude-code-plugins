---
bump: patch
---

### Fixed

- A work-resolve-issue run that finds, just before it opens its PR, that a trusted open PR already closes the issue now stops `closed-by-open-pr` on the `wait` route, naming that PR in its `outcome=wait pr=<n>` marker, instead of `retry`. work-unblock then leaves the issue alone while that PR is open and starts it again only once the PR merges or closes unmerged, so the issue is not queued for another build while a person's PR for it is open. When the PR has already closed by the time the stop is written, the stop falls back to `retry`.
