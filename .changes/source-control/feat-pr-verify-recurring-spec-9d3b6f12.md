---
bump: minor
---

### Added

- The verify gate counts a recurring-schedule issue as a trusted spec. A linked issue that
  github-actions[bot] filed, whose body has exactly one `<!-- recurring-schedule id=<id> -->` line
  naming exactly one row of the default branch's `.github/recurring-schedule.json`, no longer
  refuses a pass `verify:untrusted-spec`, so the lanes can merge it. The schedule is read at the
  default branch's tip, never at the pull request's base or head.
