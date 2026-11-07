---
bump: patch
---

### Fixed

- The merge gate reads every page of a linked issue's comments, and of a size split's parent, up to 10 pages of 100, the same cap the pr-verify resolver reads. An issue with more than 100 comments no longer refuses every pass as unreadable. Past 1000 comments the refusal names the count and the cap; a page that does not arrive, or a failed page read, still refuses as unreadable.
