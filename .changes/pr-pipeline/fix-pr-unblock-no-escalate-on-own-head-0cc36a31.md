---
bump: patch
---

### Fixed

- fix-ci no longer hands a pull request to a person (`ci-fix-escalated`) in the same run that pushed its fix: a written patch now pushes with no escalation, whatever the model escalated beside it, and the new head's own CI decides. A red new head gets its own fix-ci run, which escalates what it cannot fix, and `loop.fix-ci-rounds` still ends the rounds with `ci-fix-round-cap` ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#prepare-apply-patch)).
