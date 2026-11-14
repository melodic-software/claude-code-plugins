---
bump: patch
---

### Fixed

- Reviewer media no longer posts a walkthrough with long silent pauses unnoticed: each moment's
  narration is sized to its frames' reading time, and a `SILENT:` moment from the render is
  lengthened or split and rendered once more, with any pause left named in the report.
