---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-vacuous-slug-test.ground-truth.yaml`) plants one defect at test/slug.test.js:15: the new accent test calls assert.ok(slugify(title), expected), which passes the expected slug as the failure message and checks only that the slug is truthy. What now fails: the test passes for any non-empty slug, main's cr-me-br-l-e for Crème brûlée included, so it cannot catch the accent bug coming back.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
