---
bump: minor
---

### Changed

- **The pull-request evidence comment shows the verifier's criterion rows as one table.** When the verdict recorded for the head carries rows from `/verification:confirm`, the comment opens with one line stating the verdict, then a Criterion, Files, Test or check, Result table in place of the per-criterion result lines. A verdict recorded without rows keeps the lines. The `ready` report's verdict line now lists the rows under it.
