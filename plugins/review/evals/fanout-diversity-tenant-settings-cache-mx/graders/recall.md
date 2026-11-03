---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-tenant-settings-cache.ground-truth.yaml`) plants one defect at src/settings.js:14: getSettings now loads settings per tenant but keeps the cache key "settings", and cached() in the unchanged src/cache.js keeps one process-wide entry per key for ten minutes. What now fails: after one tenant's checkout loads settings, every other tenant's checkout gets that tenant's currency, locale and tax rule for up to ten minutes, so a EUR store shows totals in a USD store's currency, or the reverse.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
