---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-stock-race.ground-truth.yaml`) plants one defect at src/inventory.js:14: reserve now awaits confirmSku between reading the stock level and writing it back, so the check and the write no longer run as one step. What now fails: two checkouts that reserve the last unit of a SKU at the same time both read 1 before either writes, both pass the check and both set the stock to 0, so one unit is sold twice with no error. It marks these claims wrong for this fixture: callers must change to await reserve (it was already async on main, and checkout already awaits it); src/warehouse.js or src/checkout.js changed on this branch (only src/inventory.js changed).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
