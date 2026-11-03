---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-cursor-pagination.ground-truth.yaml`) plants one defect at src/routes/catalog.js:11: the page query filters on id > the cursor's id but orders by name, and the cursor holds only the last row's id. What now fails: when id order differs from name order, a product whose id is below a page's last id but whose name sorts after it is never returned, so the nightly feed export misses products; with products 1 Zebra, 2 Apple, 3 Mango and limit 2, the first page is Apple and Mango, the cursor is id 3, and Zebra is never listed.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
