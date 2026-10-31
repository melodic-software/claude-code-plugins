---
bump: patch
---

### Fixed

- The `address-feedback`, `review-dependency` and `fix-ci` activities pass `--unattended` to `source-control:pull-request` (`comments --ci --unattended`, `dependency --ci --unattended`, `ci --ci --unattended`), and the README example's `simplify` and `check-intent` activities pass it to `code-tidying:batch-simplify` and `verification:confirm`. A skill treats a run as unattended only when its caller passes the flag, and a lane run has nobody to answer an ask. The patch and mutate-branch runners' system prompt names `/discovery:research --unattended`. A live-config test fails when a lane activity calls a skill whose argument hint lists `--unattended` without passing it ([#11546](https://github.com/melodic-software/claude-code-plugins/issues/11546)).
