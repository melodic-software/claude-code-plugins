---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-return-promise.ground-truth.yaml`) plants no defect. It marks these claims wrong for this fixture: loadProfile now returns a pending promise, so the caller gets a Promise instead of the user (loadProfile is still async, its return adopts findUser's promise, and src/routes/profile.js awaits it); a rejected lookup is no longer caught or now goes unhandled (loadProfile has no try block, so the await caught nothing on main, and the route's try block still receives the rejection); src/routes/profile.js or findUser changed on this branch (only loadProfile in src/users.js changed).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
