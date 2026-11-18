---
bump: patch
---

### Fixed

- The `confirm-lists-every-verifier-verdict` eval's `lists-both-in-order` grader passes a report that lists both verdicts in a table. Its window from "Verifier" to NEEDS WORK widens from 120 to 400 characters, so a table header no longer puts the verdicts out of reach. A wrong-order table still fails.
