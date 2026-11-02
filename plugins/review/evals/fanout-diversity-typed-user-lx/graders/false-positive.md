---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-typed-user.ground-truth.yaml`) plants no defect. It marks these claims wrong for this fixture: displayName now throws a TypeError for a null or signed-out user (headerLabel in src/header.ts returns "Sign in" before it calls displayName, and tsconfig.json's strict mode rejects a null argument); a user with no profile now throws (SignedInUser.profile is required by src/types.ts); src/header.ts changed on this branch (only src/display-name.ts changed).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
