---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-cursor-pagination.ground-truth.yaml`) plants one defect at src/routes/catalog.js:11: the page query filters on id > the cursor's id but orders by name, and the cursor holds only the last row's id. What now fails: when id order differs from name order, a product whose id is below a page's last id but whose name sorts after it is never returned, so the nightly feed export misses products; with products 1 Zebra, 2 Apple, 3 Mango and limit 2, the first page is Apple and Mango, the cursor is id 3, and Zebra is never listed. It marks these claims wrong for this fixture: a malformed after cursor crashes the route (decodeCursor returns null and the route answers 400); limit is unbounded (it is clamped to 100).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
