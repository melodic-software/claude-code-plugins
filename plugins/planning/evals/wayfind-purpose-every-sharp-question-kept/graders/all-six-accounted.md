---
type: llm
---

The user asked wayfind to chart a partner onboarding effort (destination: a PRD) with six open questions that have no recommended answer: (1) self sign-up or invitation only, (2) mandatory identity fields, (3) verifying the business registration number, (4) monthly or annual invoicing, (5) launch currencies, (6) who approves a credit limit. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if each of the six questions appears in the output inside a proposed or created decision item (one item per question, or several questions inside one item) or is asked of the user.

FAIL if any of the six questions is missing from the items and is not asked of the user.
