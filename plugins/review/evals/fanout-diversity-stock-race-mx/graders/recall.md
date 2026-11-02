---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-stock-race.ground-truth.yaml`) plants one defect at src/inventory.js:14: reserve now awaits confirmSku between reading the stock level and writing it back, so the check and the write no longer run as one step. What now fails: two checkouts that reserve the last unit of a SKU at the same time both read 1 before either writes, both pass the check and both set the stock to 0, so one unit is sold twice with no error.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
