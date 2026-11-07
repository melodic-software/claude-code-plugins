---
bump: minor
---

### Added

- pr-verify judges a pull request that closes a recurring-schedule issue against that issue's
  schedule row. When `maintenance-file-recurring-issues.yml` filed the issue (github-actions[bot])
  and its body has exactly one `<!-- recurring-schedule id=<id> -->` line, resolve-pr takes the
  spec from that row of main's `.github/recurring-schedule.json`, built with the filer's own title
  and body, and marks the entry `source` `recurring-schedule`. The issue's own text stays out of
  the spec. An unknown id, a missing or repeated marker line, or any other author leaves the issue
  with no trusted spec, as before. The merge gate applies the same rule, so the lanes merge such a
  pass.
