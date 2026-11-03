---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-tenant-settings-cache.ground-truth.yaml`) plants one defect at src/settings.js:14: getSettings now loads settings per tenant but keeps the cache key "settings", and cached() in the unchanged src/cache.js keeps one process-wide entry per key for ten minutes. What now fails: after one tenant's checkout loads settings, every other tenant's checkout gets that tenant's currency, locale and tax rule for up to ten minutes, so a EUR store shows totals in a USD store's currency, or the reverse. It marks these claims wrong for this fixture: a missing tenant id reaches the database (getSettings throws first); an unknown host reaches checkout with no tenant (resolveTenant answers 404 first).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
