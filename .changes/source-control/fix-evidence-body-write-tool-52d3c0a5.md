---
bump: patch
---

### Fixed

- **`reference/evidence.md`, step 4.** The instruction to write the comment body with the Write
  tool now comes once, after the placeholder list, with a literal target
  (`<dir>/evidence-comment.md`, the scratchpad or the path `mktemp -d` prints), every path and
  value filled in literally, and its reason: the Write tool's content reaches no shell, so a
  `$(...)` or backtick in the criterion or summary text stays text. Steps 5 and 8 read that file.
