---
bump: minor
---

### Changed

- Repeat queue ejections: `merge.max-queue-ejections` now counts only merge-queue removals that follow a failed `merge_group` run. Removals that follow a cancelled run have their own cap of 2, and the gate tells the two apart by pairing each removal with the pull request's newest merge group by time ([#8566](https://github.com/melodic-software/claude-code-plugins/issues/8566)). Under `merge.lane-prs: native`, enable-auto-merge applies both caps, so its next scheduled run re-arms a lane pull request that a cancelled run removed. The README now says pr-merge re-queues only its own candidates: the session or person that merged a pull request outside it watches that pull request's queue entry (owner decision, 2026-10-20).
