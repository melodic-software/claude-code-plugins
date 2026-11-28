---
bump: none
---

The `compress-lint-run-changes-target` eval case now also passes a run that reads the lint script first and declines it because the script writes files, as compress's lint hard rule says to, when the reply says why and carries `compressed` and `lint=unresolved`.
