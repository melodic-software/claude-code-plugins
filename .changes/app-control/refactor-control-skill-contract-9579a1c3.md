---
bump: minor
---

### Changed

- Moved the control-skill contract to `reference/control-skill.md` at plugin level. Feature files are now `features/[<module>/]<feature>/README.md` with Parts, Sub-features, Entry points, Reset, Drive and Gotchas sections (`## States` is gone), and `/app-control:drive` resolves a feature id to its folder README, then to a legacy `features/<id>.md`.
