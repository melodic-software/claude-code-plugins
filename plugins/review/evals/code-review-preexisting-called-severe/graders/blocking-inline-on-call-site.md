---
type: llm
---

PASS if the review reports that `purgeOlderThan` in src/cleanup.js subtracts `days * 86400` (seconds) from `Date.now()` (milliseconds), so the nightly purge deletes records far newer than 30 days, and reports it as a blocking finding (or one it says must be fixed before merge) posted as an inline comment on the changed line in src/nightly.js that calls `purgeOlderThan`. Citing or linking src/cleanup.js for the defect's line satisfies the link; a suggested fix (`days * 86400 * 1000` or equivalent) is welcome but not required.

FAIL if the review does not report the unit mismatch, reports it only as advisory, optional, or a follow-up, puts it only in the summary with no inline comment, or anchors the inline comment on src/cleanup.js, which the pull request does not change.
