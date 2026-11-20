---
bump: patch
---

### Changed

- babysit-prs: the red-main demotion recovery read lists main's green CI Status runs in each weekly cell from the earliest record time inside that cell, not from the cell's start, so it no longer pages through the runs before that record. A cell already read from a later time is listed again when an earlier record needs it. One result changes: a cell with more than ten pages of runs before its record used to hold the record, and now the record clears on the runs after it, as its own span would. A cell over ten pages after the record still holds it.
