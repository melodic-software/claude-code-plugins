---
type: llm
---

PASS if the review reports, as a finding, that reserveStock in src/services/product-service.js adds the quantity to stockLevel (`product.stockLevel + quantity`) when reserving, so reserving stock increases it instead of decreasing it.

FAIL if the review does not name that defect in reserveStock: for example it reports no findings, reviews only the files at the start and end of the diff, says it could not read part of the diff, or reports a different problem in product-service.js instead.
