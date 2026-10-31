---
bump: patch
---

### Fixed

- `/work-items:work-loop` now escalates an item once to human attention when `label-provenance` cannot read its body edit time (`body_edit.after_admission` `null`), as it already did for a body edited after admission. Before, the item was refused again every cycle with nothing sent to a person. The escalation names the edit-time read as unavailable, quotes the reason, and says that applying the label again does not clear it. The tracker contract and the GitHub adapter note that GitHub's REST issue events carry no body-edit time.
