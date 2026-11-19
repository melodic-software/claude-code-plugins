---
bump: patch
---

### Changed

- pr-unblock-dispatch spends fewer core GITHUB_TOKEN calls and makes the same dispatch decisions. fix-ci reads a head's required run before its fix-ci and push-job check runs, so a head that the required run, a re-run, or a hold skips does not read those two lists. fix-docs reads the PR's check-run history (GraphQL) before the pr-refine.yml runs listing, so a PR the history already settles skips that REST listing. It reads a green run's latest jobs without a separate run read, because the listing already gives the run's status.
