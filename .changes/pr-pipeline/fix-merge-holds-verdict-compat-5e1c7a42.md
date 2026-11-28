---
bump: patch
---

### Fixed

- `merge-holds.mjs` prints `no member veto and no hold path.` again when nothing holds, the verdict line both the current and the older ci-status queue step accept, so a pull request whose head still carries the older workflow no longer fails with `merge-holds.mjs exited 0 without its verdict.`
