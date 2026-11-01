---
bump: patch
---

### Fixed

- `/planning:interview` names the `resolve-convention-home.sh` command in its EARS spoke and has it run before any `AGENTS.md`, `CLAUDE.md` or `authoring-formats/README.md` read for `acceptance_criteria_format`, so a repository whose pointer line names a non-default convention home gets its own format instead of the default path's.
