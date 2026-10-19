---
bump: minor
---

### Added

- A skill leaf's optional `self-checks`: repository check scripts with fixed flags, the same shape as
  `checks`, that the skill runs and fixes before it commits through the same wrapper. They are
  advisory: unlike `checks`, the issue lane's run-checks job never reruns them, so a failure the
  skill cannot fix still opens the PR and is named in its report. `work-resolve-issue`
  `resolve-issue` lists `scripts/check-affected.sh --uncommitted`, which checks the work tree as
  the commit the API would make, with untracked files and file modes included, and leaves the
  checkout's HEAD and index as they were. `version` stays 2.

### Changed

- The checks copy also carries the base's `.shellcheckrc`, `.markdownlint-cli2.jsonc` and
  `.github/requirements-ci.txt`, which `check-affected.sh` and `run-ruff.sh` read. A check's
  wrapper unsets `GH_TOKEN` and `GITHUB_TOKEN` and pins git config the way a verify-script's wrapper
  does. A skill with checks is told to fix what a check reports in the working tree and to name
  anything it could not fix in its report; a skill that commits is told to run the checks, fix,
  and run them again before it commits.
