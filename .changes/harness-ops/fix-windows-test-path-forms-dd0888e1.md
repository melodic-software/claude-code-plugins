---
bump: patch
---

### Fixed

- `/harness-ops:changelog` `status` prints the default ledger path in the shell's own form on Git
  for Windows (`/d/repo/...`), the same form it prints outside a repository, instead of the `D:/`
  form `git rev-parse --show-toplevel` returns there.
