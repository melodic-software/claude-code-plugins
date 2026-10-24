---
bump: minor
---

### Changed

- `/work-items:work --ci` keeps a progress note, `.lane-progress.md` at the checkout root. It reads the note before any other work. It works in small, complete increments, so the tree is coherent wherever the run ends. After each finished piece or settled decision it rewrites the note under Done, In progress, Next, Decisions and Dead ends. It deletes the note in the change it reports done. A long issue run carries its context from one job to the next this way.
