---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-null-user.ground-truth.yaml`) plants one defect at src/display-name.js:2: displayName drops its check for a missing user or profile, on the commit message's claim that every caller passes a signed-in user. What now fails: renderHeader in src/header.js passes session.user, which is null until the visitor signs in, so displayName reads .profile of null and throws a TypeError for every signed-out visitor; a user with no profile fails the same way. It marks these claims wrong for this fixture: src/header.js changed on this branch (only src/display-name.js changed); a signed-in user with a profile now gets a different name (that path is unchanged).

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
