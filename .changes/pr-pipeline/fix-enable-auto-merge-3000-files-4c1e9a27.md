---
bump: patch
---

### Fixed

- `enable-auto-merge` reads a pull request's changed files up to the 3000 GitHub's files listing returns, instead of refusing every pull request over 300 files for a person; a listing that reaches 3000 still fails closed to a person.
