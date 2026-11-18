---
bump: patch
---

### Changed

- The `update` action's safety table states the current rule: the marketplace's daily drift workflow runs `--check` and files an `Upstream drift: playwright/playwright` issue when upstream moves, the issue lane runs `--apply` and the reference integration, and the change merges through a reviewed pull request. It no longer says nothing runs on a schedule. The README says the check runs daily and that the issue lane works the issue.
