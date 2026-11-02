---
bump: patch
---

### Changed

- `write-for-agents`: "Ask for outcomes, not thinking" states the decision in this skill's words (depth through the effort level, a bounded rationale in place of the model's reasoning) and moves the per-model specifics to a pointer record on the Opus 5.5 prompting guide (#12359).

### Added

- Three eval cases for that paragraph: `wfa-think-steer-to-effort`, `wfa-reasoning-echo-bounded` and `wfa-dont-think-to-effort`.
