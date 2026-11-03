---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-request-options.ground-truth.yaml`) plants 2 defects. This grader checks defect 1, at src/http/options.js:16: when a caller passes a token but no headers, buildOptions writes the Authorization header into the shared DEFAULTS.headers object, because opts.headers is still that object. What now fails: after one signed-in profile() or orders() call, every later request built without headers, such as the anonymous priceList() call, sends that user's bearer token, so the token goes to the CDN-cached price list and anonymous requests run as that user.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count. A finding about another planted defect does not count.
