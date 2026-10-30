---
bump: patch
---

### Changed

- `/planning:interview`, `/planning:prd` and `/planning:design` resolve their authoring-formats keys through one shared ladder in `context/authoring-formats.md` instead of three restated copies; no behavior change. New eval cases cover the `ears` path in interview and prd and the `dbml` path in design.
