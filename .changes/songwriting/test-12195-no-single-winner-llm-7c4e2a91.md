---
bump: patch
---

### Changed

- The three menu cases' `no-single-winner` grader is now LLM-judged in place of a regex: a reply passes when it leaves the choice to the writer and fails on a lone pick, with or without its option number.
