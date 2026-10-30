---
bump: patch
---

### Changed

- The merge gate runs the shared YAML reader once per config text and key list in a process, not once per commit: the post-merge check reads the pipeline config at every merge since its floor, and those reads spawned about 14,600 reader processes per candidate. A replayed gate run on one candidate drops from 138 to 44 seconds of local work, with the same verdict.
- A gate candidate no longer re-runs a post-merge check that already came back unreadable at main's current head, from the same floor, identity and lane, within the shared answer's age: it is refused with that check's reason. The merge job's own exit-3 check counts as that one check, so an unreadable day costs one check per sweep instead of one per candidate (about 50 gh calls and 4 minutes each). A check that comes back unreadable is still a hold, never a pass.
