---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-page-links.ground-truth.yaml`) plants no defect. It marks these claims wrong for this fixture: the <= bound in pageNumbers is off by one and adds an extra page (pageCount is the last 1-based page number, so the loop pushes 1 through pageCount as main did); pageNumbers(0) now returns [1] (pageCount is 0, so the loop body never runs); the first page is now skipped (the loop starts at page 1, the first 1-based page).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
