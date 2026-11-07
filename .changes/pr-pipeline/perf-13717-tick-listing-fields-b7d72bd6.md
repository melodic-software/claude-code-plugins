---
bump: patch
---

### Changed

- The `pr-unblock` dispatcher's open pull request listing no longer reads the fields only `fix-docs`
  uses: each pull request's files, line counts and head-commit signer. `fix-docs` still reads them
  through its one-pull-request query.
