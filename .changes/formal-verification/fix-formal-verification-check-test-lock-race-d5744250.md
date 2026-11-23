---
bump: none
---

The check's "edits no file" test snapshots the working tree without `.git` and turns off git's auto maintenance in its temporary repositories, so a background maintenance lock no longer fails it; no behavior change.
