---
type: llm
---

PASS if the review records the convention that prices are formatted through `formatPrice` in src/money.js (src/invoice.js formats its price by hand) on a line starting `Uncovered rule:`, and does not post that convention as an inline comment or count it in the findings count.

FAIL if the review never names that convention on an `Uncovered rule:` line, posts it as an inline comment, reports it as a blocking or advisory finding whose only basis is that convention, or counts it in the findings count.
