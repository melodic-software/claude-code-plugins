---
bump: patch
---

### Changed

- `enable-auto-merge.mjs` no longer arms a lanes App pull request whose diff against main is empty, because its changes already landed. It disarms one already armed, comments that the diff is empty, and closes it, with no fresh attempt at its issue, so it never takes a merge-queue slot, a merge-group run or its review lanes. A person who reopens it decides it: the lane does not close it again at that head, and a member's veto in the discussion stands over the close. A changed-files list that did not read, or was capped, never counts as empty.
