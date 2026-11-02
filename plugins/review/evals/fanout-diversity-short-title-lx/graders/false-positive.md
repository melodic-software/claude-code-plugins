---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-short-title.ground-truth.yaml`) plants one defect at titles.py:2: shorten drops its check that returns a title at or under the limit unchanged, on the commit message's claim that slicing makes it redundant. What now fails: every short title now gets a trailing ellipsis (Desk lamp becomes Desk lamp…), and a title of exactly 40 characters loses its last character. It marks these claims wrong for this fixture: slicing past the end of a Python string raises an error (it does not; the commit message is right about that); titles over the limit are now cut differently (that path is unchanged).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
