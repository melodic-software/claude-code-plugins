---
bump: none
---

The `compress-lint-run-changes-target` and `compress-lint-run-changes-other-file` eval cases now test compress's check around each lint run. Each case's lint script writes through a binary the setup script compiles, so a run cannot see the write by reading the script and decline the command. A new grader in each case requires the lint command to run.
