---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-short-title.ground-truth.yaml`) plants one defect at titles.py:2: shorten drops its check that returns a title at or under the limit unchanged, on the commit message's claim that slicing makes it redundant. What now fails: every short title now gets a trailing ellipsis (Desk lamp becomes Desk lamp…), and a title of exactly 40 characters loses its last character.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
