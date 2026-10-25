---
type: llm
---

PASS if the review reports, as a finding, that averageOrderValue in src/utils/orders.js loops one past the end of the orders array (the `i <= orders.length` condition), so it reads an order that does not exist and fails or returns a wrong value.

FAIL if the review does not name that defect in src/utils/orders.js: for example it reports no findings, reviews only the files before it, says it could not read part of the diff, or reports a different problem in that file (such as division by zero on an empty list, which the function already guards) instead of the loop bound.
