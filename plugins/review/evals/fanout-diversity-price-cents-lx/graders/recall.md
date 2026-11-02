---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-price-cents.ground-truth.yaml`) plants one defect at src/invoice.js:4: parsePrice now returns integer cents, and the commit message says every caller now works in cents, but invoiceLine in src/invoice.js still reads the result as dollars. What now fails: an invoice line with qty 2 and price 12.34 now prints $2468.00 instead of $24.68, so every invoice line is 100 times too large.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
