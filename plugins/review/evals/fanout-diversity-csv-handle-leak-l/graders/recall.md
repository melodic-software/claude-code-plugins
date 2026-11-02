---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-csv-handle-leak.ground-truth.yaml`) plants one defect at src/import-csv.js:10: countRows drops its try/finally and throws on a wrong header before file.close() runs. What now fails: a CSV whose first row is not sku,qty,price, or one whose read fails, throws with its file handle still open; importAll catches each file's error and goes on, so a nightly batch with many bad uploads leaves one handle open per bad file until garbage collection, and enough of them make later opens fail with EMFILE.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
