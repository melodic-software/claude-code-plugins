---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-sort-column.ground-truth.yaml`) plants no defect. It marks these claims wrong for this fixture: the ORDER BY clause interpolates req.query.sort into the SQL (only a value from the SORT_COLUMNS map reaches the query, and an unknown sort falls back to name); the search term q is injectable (it is bound as a ? parameter); a sort such as constructor or toString reaches the SQL (SORT_COLUMNS is a Map, so get returns undefined for it and the query sorts by name).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
