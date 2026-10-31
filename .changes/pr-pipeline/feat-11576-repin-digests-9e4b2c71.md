---
bump: minor
---

### Changed

- `resolve-issue` lists `plugins/planning/scripts/repin-digests.sh` as a `verify-script`, so the
  issue lane can re-pin a planning interview digest without a host session. The script runs
  nothing from the checkout: it reads the test file and the files the test pins as data and
  computes each digest with its own base copy's helpers. `tests/repin.sh` also runs the test, so it
  stays off the list, and the pull request's CI still runs the test.
