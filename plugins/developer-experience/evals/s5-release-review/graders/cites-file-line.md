---
type: llm
---

The user asked: "Review `bfk release` as a command-line tool. Don't change anything yet." The reply lists gaps (problems) in the command.

For every gap the review lists, check that it cites a file and line, such as `bfk/release.py:7`, `release.py` line 7, or a line range.

PASS when every listed gap has a file:line citation. Summary sentences that repeat already-cited gaps, sub-points under a cited gap, and suggested fixes need no citation of their own.

FAIL when at least one gap has none.
