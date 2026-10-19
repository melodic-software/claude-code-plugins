---
bump: minor
---

### Changed

- Shorter bodies for `co-write`, `diagnose`, `meter-prosody`, `object-writing`, `practice`, `rhyme`, `setup`, `song-form` and `suno`, and shorter descriptions for every skill except `metaphor`, `practice` and `rhyme`. Eval cases and trigger probes measured each change against the old text before it shipped, except `setup`, which is user-invoked only and shipped on a meaning diff. `metaphor` keeps its original description and body, `practice` and `rhyme` keep their original descriptions, and `workflow` keeps its original body, because the shorter text scored lower.

### Added

- Ten outcome eval cases under `evals/`, one per measured skill, and frozen trigger-probe sets under `probes/`.
