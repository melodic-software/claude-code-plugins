---
bump: minor
---

### Added

- `/user-interface:glossary`, a model-invoked reverse term lookup: given an effect, visual detail or behavior someone can describe but not name, it answers with the term, separates near-synonyms, turns a vague feel request into named terms, and asks for a reference image when no term fits. Its term files list starts with `reference/motion.md`.

### Changed

- The animation glossary moved from `reference/animation/glossary.md` to the glossary skill's `reference/motion.md`; the animation catalog now points at `/user-interface:glossary` for effect names.
