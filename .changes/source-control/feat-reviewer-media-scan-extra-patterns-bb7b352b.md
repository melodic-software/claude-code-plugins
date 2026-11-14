---
bump: minor
---

### Added

- `/source-control:pull-request media` takes `--scan-pattern <regex>` (repeatable): the leak scan also refuses those patterns, the `reviewer-media` convention's `scan.extra_patterns`. It adds to the floor and never replaces it; a pattern that does not compile refuses with exit 5.
