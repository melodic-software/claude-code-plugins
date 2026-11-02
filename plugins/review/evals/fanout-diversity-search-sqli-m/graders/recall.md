---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-search-sqli.ground-truth.yaml`) plants one defect at src/routes/search.js:11: the new public /search route concatenates the q query parameter into its SQL LIKE clause. What now fails: an unauthenticated caller can inject SQL through q, for example a UNION SELECT that returns the users table's emails and password hashes; the fix binds the term as a parameter, as src/routes/products.js does.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
