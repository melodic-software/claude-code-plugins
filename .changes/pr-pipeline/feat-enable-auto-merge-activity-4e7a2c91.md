---
bump: minor
---

### Added

- The pr-merge lane's `enable-auto-merge` activity (effect `merge`) turns on GitHub's native auto-merge, squash at the head it read, for each open lanes App pull request into main that opens with `Closes #<issue>` and carries no hold (a `Hold:` line or "do not merge" in its body, `do-not-merge`, the human-gated label, a member's newest comment saying "do not merge", a head that now changes a denied path), and turns it off on an armed one that now carries a hold. Auto-merge a person turned off stays off. `pr-merge.yml` runs it in its own job, with its own lanes App token, when the issue lane finishes (a new `workflow_run` trigger the merge job ignores), on a listed human's edit, unlabel or ready, and on the schedule. While `merge.report-only` is true it writes nothing ([README.md, Native auto-merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#native-auto-merge)). `ci-status` fails a lanes App pull request on a body hold, a member's veto comment or a changed or renamed-from denied path, on each pull request event and in the merge queue, so a hold added after arming stops the merge.
