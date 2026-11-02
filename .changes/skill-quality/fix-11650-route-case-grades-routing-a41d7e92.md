---
bump: patch
---

### Fixed

- The `ve-new-evals-route-to-suite` case drops its `skill-fired` grader. `/skill-quality:check`'s description routes new eval cases to `/evals:validate`, so the right answer need not fire the skill; the case's other graders grade that routing.
