---
bump: patch
---

### Fixed

- `babysit_merge.py --unattended` no longer adds the human-gated label back after a person removed it: a User of kind `human` on the trusted-actor list read at the repository's default branch, with write access. The escalation is the risk, verifier, held-major or shared-copy one, its comment is unchanged (same head and reasons), and the label's newest removal was that person's, after the comment last changed. The run reports `label: lifted`. A removal by a bot, the lanes App included, by an account off that list, or made through a GitHub App lifts nothing. A new head or new reasons escalate again. An unreadable timeline or default branch adds the label as before, and the run reports why as `liftUnread`.
