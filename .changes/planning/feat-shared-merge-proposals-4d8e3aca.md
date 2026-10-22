---
bump: minor
---

### Added

- The shared interview page: Claude proposes merging a person who joined again on another device or browser into the earlier person, or letting in a join that waits, with its reasons. The host approves each with one tap (Merge or Let in) or dismisses it in the Host view and the Inbox; nothing merges or lets anyone in without that tap, and the owner is never merged or proposed. The server tells Claude about such joins with a new `person-joined` event, and Claude answers with the new `propose-merge` and `propose-admit` ops.
