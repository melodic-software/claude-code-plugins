---
bump: patch
---

### Fixed

- The `confirm-lists-every-verifier-verdict` eval's `final-confirmed` grader passes a report that gives the final verdict in a table cell as `CONFIRMED (final)`. A table whose final verdict is NEEDS WORK still fails, as does an answer that lists CONFIRMED without stating it final.
