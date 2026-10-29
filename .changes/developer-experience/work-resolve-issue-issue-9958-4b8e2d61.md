---
bump: patch
---

### Added

- Eval cases `s2-tracker-comment` and `s5-release-review`, ported from scenarios S2 and S5 on the shared fixtures. `s2-tracker-comment` checks that posting a tracker comment runs the existing `tq item comment` command, creates no source, script or project file and writes or edits none with the Write or Edit tool, and calls neither build-cli nor audit-tools. `s5-release-review` judges whether a review of `bfk release` reports the interactive-only confirmation and the missing `--yes` bypass, with a file:line for each gap. It also checks that the review creates no file, makes no Write or Edit call, and runs no shell command that deletes, moves, edits in place or resets files, including one inside a compound command (#9958).
