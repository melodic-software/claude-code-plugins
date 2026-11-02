---
bump: patch
---

### Fixed

- `/review:code-review` and its `lane-verifier` hunters now cite each finding's `file:line` as the line in the file at the PR head, counted from the hunk header's `+<start>` over context and added lines. They no longer cite a line number inside the diff file the wrapper names, which put an inline comment on the wrong line. A verifier gives the head file's line when a candidate cites a different one.
