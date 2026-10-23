---
bump: minor
---

### Changed

- The `enable-auto-merge` activity arms a lanes App pull request whose issue link the merge gate takes, a plain `Refs: #<n>` issue included, instead of only one whose body opens with `Closes #<issue>`. The link is read with the verdict, through the gate's own rule (`babysit_verify_evidence.py evidence --lane-link`, which runs `babysit_merge_policy._linked_issue`), on the scheduled and hand-started runs only: two or more `Refs:` issues, a `Refs:` line in any other form, a number that is no issue, two closing issues, a closing issue in another repository, and a failed read all leave the pull request unarmed, or disarm it. An event run reads no link, so it never disarms on one.
- The `enable-auto-merge` activity applies the merge gate's run-level refusals, which native auto-merge would otherwise skip. Each scheduled or hand-started run runs the post-merge check, as the merge job does, and reads the lane's room from it (`babysit_verify_evidence.py lane-room`, `babysit_merge_policy.lane_room`). While a demotion record, `merge.rung`, the loop setting or the rung cap holds the lane off, or a lane merge failed its post-merge check, nothing is armed and every armed lanes App pull request is disarmed. At `merge.max-in-flight`, counting the queue's lane entries, the lane's unverified merges and armed pull requests not yet queued, nothing more is armed. A room that cannot be read arms nothing and disarms nothing. The job now holds `pull-requests: read` and `issues: read` for those reads.
