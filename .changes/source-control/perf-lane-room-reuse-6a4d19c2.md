---
bump: patch
---

### Changed

- `/source-control:babysit-prs`: `settle_shared` keeps a post-merge answer refused as `unverified-stale` when the only thing that tripped is the demotion probe and `read_demotion` reads the same demotion, as it already keeps a `demotion-changed` answer. Before, any edit to an issue the lane opened made the lane room run a full post-merge check, and made the merge job's `settle` and post-merge-dispatch's idle-tick reuse refuse the report. All three take the new keep. A demotion that differs, or a demotion read that fails, still refuses. The merge gate's own keep in `assess` is unchanged.
- The `lane-room` report gains `postMerge`: `answer` (`reused`, `kept`, `recomputed` or `refused`), `reason` (the reuse refusal behind any but `reused`) and `moved` (for an `unverified-stale` answer not kept: `head-moved`, `config-moved`, `demotion-changed`, `runs-moved` or `unreadable`). enable-auto-merge's `lane room:` log line prints it, so a slow room read shows why it ran the check.
