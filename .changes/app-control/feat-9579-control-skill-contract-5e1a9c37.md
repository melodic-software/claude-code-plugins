---
bump: minor
---

### Added

- `/app-control:drive` resolves a feature id, `<feature>` or `<module>/<feature>`, to `features/<id>/README.md` first and then to a legacy flat `features/<id>.md`; an id that matches neither is reported as not found with the index's feature paths, and nothing is driven.
- Two eval cases, in the skill's `evals.json` and as plugin eval cases: a grouped id that resolves to its feature folder before a flat file at the same id, and a single-level id that resolves to a legacy flat file.

### Changed

- The control-skill contract moves to the plugin level, `reference/control-skill.md`, so every skill in the plugin cites one file. Each feature is now a folder, `features/[<module>/]<feature>/README.md`, with the sections Parts, Sub-features, Entry points, Reset, Drive and Gotchas, and every entry point ends `driven` or `not driven: <reason>`. The hub index line is `- <title> | features/[<module>/]<feature>/README.md | entry points: <n> | sources: <glob>[, <glob>]`. A legacy flat feature file still resolves.

### Removed

- The `## States` feature section.
