---
bump: patch
---

### Changed

- The revert eval cases keep their fixtures as plain-text `.txt` byte copies under each case's
  `fixtures/` directory instead of a `fixtures.tar.gz` archive, so no binary is committed and
  reviewers can read every file. `revert-cases.sh build` writes that directory and `scaffold`
  rebuilds the workspace from it, refusing a case with no `fixtures/` directory.
