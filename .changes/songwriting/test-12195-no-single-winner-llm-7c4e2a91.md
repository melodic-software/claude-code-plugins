---
bump: patch
---

### Changed

- The three menu cases' `no-single-winner` grader is now LLM-judged in place of a regex: a reply passes when it leaves the choice to the writer and fails on a lone pick, with or without its option number.
- The two rhyme menu cases' `eight-plus-candidates` grader is now LLM-judged in place of a regex: it counts distinct candidates however they are laid out (list lines, table rows with several per row, or inline), not lines or rows, and does not count a candidate named only to rule it out.
