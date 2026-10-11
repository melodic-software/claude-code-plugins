---
bump: patch
---

### Fixed

- **The shared `yaml-subset.awk` parser trims trailing blanks and strips trailing comments (a `#` after a space) in one pass**, where two regexes rescanned a long run of spaces from every start; a 200,000-space line now parses in well under a second with the same records.
