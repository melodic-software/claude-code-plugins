---
bump: patch
---

### Fixed

- `check-signed-commits` waits up to 60 s, backing off 5, 10, 20 and 25 s, for the pull request's head to match its branch before it gives up, instead of 8 s, since GitHub's pulls API can lag a push by minutes.
- `report-check-run` posts "The lane's commits could not be verified." when the signed-commit check failed without naming an unverified commit, and keeps "not GitHub-verified" for a named one. It takes the check's `unverified` output as a new input.
