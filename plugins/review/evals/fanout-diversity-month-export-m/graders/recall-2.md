---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-month-export.ground-truth.yaml`) plants 2 defects. This grader checks defect 2, at src/export.js:17: the sort comparator returns a boolean, never a negative number. What now fails: sort reads true as 1 and false as 0, so it never moves a later row ahead of an earlier one and rows stay in database order; imported orders, whose row order does not follow created_at, come out unsorted instead of oldest first.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count. A finding about another planted defect does not count.
