---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: a pure rename or copy no longer holds for a person as `unreviewed-patch:<path>`. The files API sends no patch for one, so every such rename read as an unreviewed binary. `ChangedFile` gains `content_unchanged`, which the merge lane sets only when the base tree's blob and mode at the old path equal the head tree's at the new path; a differing blob, a changed mode or an id either tree lacks still holds.
