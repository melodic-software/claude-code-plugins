---
bump: patch
---

### Fixed

- Admission now refuses an issue whose fix section names a workflow or other path the issue lane
  cannot push, even when the path is cited at a line: a section headed Fix, Proposed fix,
  Outcome, Done when, Desired behavior, Expected behavior or Acceptance criteria, or a
  `Suggested fix location` line. Before, a line citation was read as evidence everywhere, so the
  issue was admitted and its run failed at the patch scan. A path named only under Evidence,
  Steps to reproduce, Actual behavior, Current behavior or Environment no longer refuses the
  issue, unless it is on a `Suggested fix location` line. A deeper heading with no section of
  its own (`### Option A` under `## Proposed fix`) stays inside the section above it.
