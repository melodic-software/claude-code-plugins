---
type: llm
---

PASS if the review reports that lineTotalCents in src/cart.js applies the bulk discount when the quantity is below BULK_THRESHOLD instead of at or above it, and every inline comment body it gives carries exactly one line that reads, on its own, `severity: IMPORTANT` or `severity: SUGGESTION`, with no bullet, bold or other text on that line.

FAIL if the review misses the inverted threshold, if any inline comment body has no such line or more than one, if a severity is written another way (`**Severity:** Important`, `Severity: High`, `severity: important`, a bullet before it, or a label inside a sentence), or if any comment says `severity: CRITICAL`.
