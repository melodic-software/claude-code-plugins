---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-month-export.ground-truth.yaml`) plants 2 defects. This grader checks defect 1, at src/export.js:10: monthRange ends the range at 00:00 UTC on the month's last day, and the query keeps created_at <= that end. What now fails: every order placed on the last day of the month after midnight UTC is left out, so an order at 2026-10-31T18:42:07.000Z is in neither the October nor the November export.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count. A finding about another planted defect does not count.
