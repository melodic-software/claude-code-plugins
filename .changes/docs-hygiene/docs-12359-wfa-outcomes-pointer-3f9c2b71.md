---
bump: patch
---

### Changed

- `write-for-agents`: "Ask for outcomes, not thinking" states the decision in this skill's words (depth through the effort level, checked per model against audit-instructions I8-f and I8-c) and moves the per-model specifics to a pointer record on the Opus 5.5 prompting guide (#12359).

### Added

- Three eval cases for that paragraph: `wfa-think-steer-to-effort`, `wfa-ultrathink-keyword-to-effort` and `wfa-dont-think-to-effort`.
