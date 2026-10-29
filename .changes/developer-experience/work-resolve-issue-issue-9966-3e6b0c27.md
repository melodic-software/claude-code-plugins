---
bump: patch
---

### Added

- Eval cases `s3-script-cleanup` and `s6-tool-inventory`, ported from scenarios S3 and S6 of the eval scenario sources onto the shared fixtures in their converged state. Each grades the scenario's answer key, file citations and other judge items with `llm` graders, and its read-only items with free graders: no `Write`, no `Edit`, and no `rm` or `git rm`, including one inside a compound shell command. A further grader records whether `/developer-experience:audit-tools` ran. ([#9966](https://github.com/melodic-software/claude-code-plugins/issues/9966))
