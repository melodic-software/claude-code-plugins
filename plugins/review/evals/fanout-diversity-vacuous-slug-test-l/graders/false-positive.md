---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-vacuous-slug-test.ground-truth.yaml`) plants one defect at test/slug.test.js:15: the new accent test calls assert.ok(slugify(title), expected), which passes the expected slug as the failure message and checks only that the slug is truthy. What now fails: the test passes for any non-empty slug, main's cr-me-br-l-e for Crème brûlée included, so it cannot catch the accent bug coming back. It marks these claims wrong for this fixture: slugify still keeps accents (it normalizes to NFD and strips the combining marks); slugify's output for a plain ASCII title changed (NFD leaves ASCII as it is).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
