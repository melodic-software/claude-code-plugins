---
bump: minor
---

### Added

- The `reviewer-media` convention gains `scan.extra_patterns`: Python regexes the secret and machine-data scan also refuses, such as a private codename. `/review:reviewer-media` passes each one as `--scan-pattern` to the renderer, the voice and `/source-control:pull-request media`. The list is add-only: a personal override adds to the team's patterns instead of replacing them, and nothing lowers the built-in floor. While a pattern does not compile, the skill skips before claiming the head and names it, so fixing the team file lets the next run build.
