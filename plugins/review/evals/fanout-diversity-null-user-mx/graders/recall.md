---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-null-user.ground-truth.yaml`) plants one defect at src/display-name.js:2: displayName drops its check for a missing user or profile, on the commit message's claim that every caller passes a signed-in user. What now fails: renderHeader in src/header.js passes session.user, which is null until the visitor signs in, so displayName reads .profile of null and throws a TypeError for every signed-out visitor; a user with no profile fails the same way.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
