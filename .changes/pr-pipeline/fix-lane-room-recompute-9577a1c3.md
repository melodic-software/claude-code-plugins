---
bump: patch
---

### Fixed

- A pending lane merge no longer makes `enable-auto-merge` disarm every armed lanes App pull request. The post-merge step takes about as long as the gate's two-minute reuse age, so the lane's room read the report as too old. It now keeps the report while nothing it was read from has moved, and otherwise checks again as the gate does. When the room is held, by a refusal or because it cannot be read, the run raises one warning annotation and one step-summary line naming the reason and each lanes App pull request it left unarmed. It posts no comment on the pull requests.
