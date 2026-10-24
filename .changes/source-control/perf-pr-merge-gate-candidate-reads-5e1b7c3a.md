---
bump: patch
---

### Changed

- The post-merge check asks the compare API once per branch tip when the branch moved after the gate's local clone was made, instead of once for every lane record. It compares the clone's copy of the branch with the live tip, and a record whose run head is on that copy is on the tip with no further call. A record off that copy, a diverged tip or an unreadable compare still gets its own compare, so every verdict is unchanged and every failed read still refuses.
- In the pr-merge lane (no `--state-dir`), the unattended gate stops a pull request the REST record reads as closed or merged right after that read, on the blocker it already gave it (`state=MERGED (not OPEN)` or `state=CLOSED (not OPEN)`), instead of running the post-merge check first. The verdict is unchanged; the gate skips the post-merge check and the queue sweep for that candidate. With a state directory, where a recorded merge request's read-back needs the full policy, the gate reads it in full as before.
