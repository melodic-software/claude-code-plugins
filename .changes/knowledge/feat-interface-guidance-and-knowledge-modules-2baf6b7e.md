---
bump: patch
---

### Security

- `/knowledge:course-digest` loads platform adapters from a static registry (`extraction/adapters/registry.js`) instead of a computed dynamic import, so a `course.json` `platform` value selects only a registered adapter and any other name, a path fragment or prototype key included, fails closed.
