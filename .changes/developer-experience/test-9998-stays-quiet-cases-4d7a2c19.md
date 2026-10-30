---
bump: patch
---

### Added

- Four stays-quiet eval cases port the source scenarios Q-build, Q-audit, NM-explain and NM-script ([#9998](https://github.com/melodic-software/claude-code-plugins/issues/9998)): an off-by-one fix in a library method, a text-helper fix with a new test, an explanation of the interactive commit command, and a fix to a build script that ignores a failed build. Each checks that build-cli and audit-tools stay out of an ordinary coding task, with deterministic graders on the files the task changes and on what it must leave alone.
