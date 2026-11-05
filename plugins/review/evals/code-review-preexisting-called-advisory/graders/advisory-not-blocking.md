---
type: llm
---

PASS if the review reports the missing-last-name defect in `formatName` (src/names.js: a user with no `last` renders as "Ada undefined"), says it predates this pull request or already reproduces on main, and reports it as advisory in the summary, with no inline comment and not as blocking or must-fix-before-merge.

FAIL if the review does not mention the formatName defect at all, reports it as blocking or as something that must be fixed before merge, says it would post it as an inline comment, or calls it a defect this pull request introduced.
