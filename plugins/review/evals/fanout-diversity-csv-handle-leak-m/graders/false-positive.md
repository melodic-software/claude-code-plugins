---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-csv-handle-leak.ground-truth.yaml`) plants one defect at src/import-csv.js:10: countRows drops its try/finally and throws on a wrong header before file.close() runs. What now fails: a CSV whose first row is not sku,qty,price, or one whose read fails, throws with its file handle still open; importAll catches each file's error and goes on, so a nightly batch with many bad uploads leaves one handle open per bad file until garbage collection, and enough of them make later opens fail with EMFILE. It marks these claims wrong for this fixture: a CSV with the expected header now gets a different row count (main also counted only the rows after the header); importAll stops at the first bad file (it catches each file's error and goes on).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
