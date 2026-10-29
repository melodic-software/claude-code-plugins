---
bump: patch
---

### Added

- Eval cases `s1-branch-start-plan` and `s4-migrator-plan`, ported from scenarios S1 and S4 of the eval scenario sources on the converged fixtures. Each grades the plan turn: build-cli fires and makes no Write or Edit call and runs no shell command that writes or deletes a file before the user says yes, and in S4 the plan asks which backup format to use and recommends neither, an `llm` grader whose samples are the labeled S4 item 10 set. ([#9953](https://github.com/melodic-software/claude-code-plugins/issues/9953))
