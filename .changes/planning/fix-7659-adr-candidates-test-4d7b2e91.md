---
bump: patch
---

### Fixed

- `/planning:design-handoff` now tests each resolved decision against the three ADR criteria (costly to undo, not obvious from the code, chosen over a live alternative) with pass or fail and one line of evidence each. It lists only decisions that pass all three, accepts "None", and names each decision that fails on a separate "Not candidates" line with the criterion it fails. Two evals cover one ADR-worthy decision among routine ones, and none.
