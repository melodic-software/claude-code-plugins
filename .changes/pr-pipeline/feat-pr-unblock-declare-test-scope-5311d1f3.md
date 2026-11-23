---
bump: minor
---

### Added

- `test-scope.apply` (boolean, default false) configures pr-unblock's fix-test-scope activity: on a same-repository pull request whose pr-require-checks run failed only at Test Selection's trace, the select job builds the missing `// test-scope:` lines as a patch, and with `apply: true` apply-test-scope pushes it as one lanes App commit.
