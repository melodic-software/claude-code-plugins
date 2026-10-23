---
bump: patch
---

### Fixed

- `babysit_merge.py --unattended` no longer adds the human-gated label back after a person removed it: a User of kind `human` on the trusted-actor list read at the repository's default branch, with write access. The escalation is the risk, verifier, held-major or shared-copy one, its comment is unchanged (same head and reasons), and the label's newest removal was that person's, after the comment last changed. The run reports `label: lifted`. A removal by a bot, the lanes App included, or by an account off that list lifts nothing. A new head or new reasons escalate again. An unreadable timeline adds the label as before.
