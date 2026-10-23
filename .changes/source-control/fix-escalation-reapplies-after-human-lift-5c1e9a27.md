---
bump: patch
---

### Fixed

- `babysit_merge.py --unattended` no longer adds the human-gated label back after a person with write access removed it. The escalation is the risk, verifier, held-major or shared-copy one, its comment is unchanged (same head and reasons), and the person removed the label after the comment last changed. The run reports `label: lifted`. A removal by a bot, the lanes App included, lifts nothing. A new head or new reasons escalate again. An unreadable timeline adds the label as before.
