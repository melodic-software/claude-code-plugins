---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-empty-ratings.ground-truth.yaml`) plants one defect at ratings.py:2: average_rating drops its early return for an empty reviews list while folding into one expression. What now fails: a product with no reviews (Cable tray in products.json) now divides by zero, so average_rating raises ZeroDivisionError and the product page fails. It marks these claims wrong for this fixture: product_page.py or products.json changed on this branch (only ratings.py changed); a product with reviews now gets a different average (the sum, division and rounding are unchanged for a non-empty list).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
