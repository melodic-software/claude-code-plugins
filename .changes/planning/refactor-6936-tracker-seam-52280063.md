---
bump: patch
---

### Changed

- `/planning:wayfind` reads and writes its decision map through `/work-items:track` actions instead of `gh`, and no longer needs `gh` or its `gh` permission grants; the map listing moved from pre-computed context to the start of each action. The `/planning:plan` template's search-before-create phase uses `/work-items:track search`, `edit --comment-file` and `add`.
