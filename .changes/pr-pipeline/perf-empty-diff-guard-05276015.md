---
bump: patch
---

### Changed

- `enable-auto-merge.mjs` no longer arms a pull request whose diff against main is empty, because its changes already landed. It refuses it with the lane's note instead, and disarms one already armed, so it never takes a merge-queue slot, a merge-group run or its review lanes. A changed-files list that did not read, or was capped, never counts as empty.
