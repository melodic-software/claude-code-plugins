---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-empty-ratings.ground-truth.yaml`) plants one defect at ratings.py:2: average_rating drops its early return for an empty reviews list while folding into one expression. What now fails: a product with no reviews (Cable tray in products.json) now divides by zero, so average_rating raises ZeroDivisionError and the product page fails.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
