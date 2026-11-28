---
bump: none
---

The `compress-lint-run-changes-target` and `compress-lint-run-changes-other-file` eval cases no longer show their lint write to a run that reads the compiled binary: its paths, open mode and appended text are decoded at run time, so the run executes the lint command and reaches compress's check around each lint run.
