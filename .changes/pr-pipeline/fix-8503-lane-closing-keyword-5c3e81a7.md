---
bump: patch
---

### Changed

- The work-resolve-issue lane's `report-outcome` checks the closing keywords in a pull request body before it opens the pull request. A body that would close an issue other than the admitted one, or close the admitted issue on a `Refs:` run, fails the run; a body that names the admitted issue nowhere gains its `Closes #<n>` or `Refs: #<n>` line.
