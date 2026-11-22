---
bump: patch
---

### Fixed

- A schedule or dispatch demotion record no longer stays open after main recovers past it until the next scheduled full run. When `pr-merge.yml`'s post-merge check proves an open record recovered, `dispatch-post-merge-runs` sends `post-merge-file-demotion-issues.yml` a `close-cleared` dispatch, and its `close-cleared` job closes the record with a comment naming the green run and its commit. The job runs one at a time. The close is github-actions[bot]'s, so it leaves the post-merge floor at the record's recovery, and a later red main files a new record. The record body now says a lane closes it once it clears.
