---
bump: patch
---

### Changed

- The post-merge check asks the compare API once per branch tip when the branch moved after the gate's local clone was made, instead of once for every lane record. It compares the clone's copy of the branch with the live tip, and a record whose run head is on that copy is on the tip with no further call. A record off that copy, a diverged tip or an unreadable compare still gets its own compare, so every verdict is unchanged and every failed read still refuses.
- An unattended gate run with no `--state-dir` (how the pr-merge lane runs) stops a pull request the REST record reads as merged before its demotion and post-merge reads, on the blocker it already gave it (`state=MERGED (not OPEN)`), instead of running the post-merge check first. The identity and queue readers are still read, so its queue sweep still dequeues a held entry. The verdict is unchanged. A closed pull request that was not merged, which can reopen, and any run with a state directory, where a recorded merge request's read-back needs the full policy, are read in full as before.
