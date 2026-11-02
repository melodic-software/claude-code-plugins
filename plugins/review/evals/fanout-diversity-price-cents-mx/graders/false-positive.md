---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-price-cents.ground-truth.yaml`) plants one defect at src/invoice.js:4: parsePrice now returns integer cents, and the commit message says every caller now works in cents, but invoiceLine in src/invoice.js still reads the result as dollars. What now fails: an invoice line with qty 2 and price 12.34 now prints $2468.00 instead of $24.68, so every invoice line is 100 times too large. It marks these claims wrong for this fixture: cartTotal is wrong (it divides the cents by 100 before formatting); parsePrice rounds a price like 0.29 to the wrong cent (Math.round turns 28.999999999999996 into 29).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
