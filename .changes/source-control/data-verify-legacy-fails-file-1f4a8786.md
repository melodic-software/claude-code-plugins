---
bump: patch
---

### Changed

- `babysit-prs`: the pr-verify verdict reader now runs in FAIL index mode. It reads a pull request's FAILs from the FAIL index plus the committed `verify-legacy-fails.json`, which lists the 550 FAILs uploaded before the index existed, instead of paging the whole artifact listing on every judgment.
