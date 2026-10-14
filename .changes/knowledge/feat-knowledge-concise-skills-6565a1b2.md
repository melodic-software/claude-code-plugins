---
bump: minor
---

### Changed

- `book-distill`, `course-digest`, `docpage-digest`, `map-corpus` and `video-digest` have shorter descriptions, one trigger per use, and tighter text in the body sections the new outcome cases reach. `setup` has a one-line description and a shorter body. Outcome eval cases and held-out trigger probes measured each change against the old text before it shipped.

### Added

- Eight outcome eval cases under `evals/` (two each for `book-distill`, `course-digest` and `video-digest`, one each for `docpage-digest` and `map-corpus`), and frozen trigger-probe sets for the five model-invoked skills under `probes/`.
