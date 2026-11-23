---
bump: minor
---

### Added

- `/evals:plugin-eval select <diff-base>` names the eval cases a change affects, split into the cases to run (the eval workflows' `cases` input), judged cases, cases to run after merge, and affected cases that need no run, with the agent-run count. It reads which skill a case tests through the shared `case_skills.py` rule and makes no model call.
