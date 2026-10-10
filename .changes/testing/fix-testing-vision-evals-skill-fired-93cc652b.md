---
bump: patch
---

### Fixed

- **The vision eval cases no longer make `run-validity` reject a run.** Each `vision-*` case is now tagged `no-trigger`, so `/evals:plugin-eval`'s run-validity check exempts it from the should-trigger rule. Their prompts say no browser is present and never ask for `/testing:run-e2e`, so a with-arm run that does not fire the skill is expected; the `skill-fired` grader stays as an unscored with-arm indicator.
