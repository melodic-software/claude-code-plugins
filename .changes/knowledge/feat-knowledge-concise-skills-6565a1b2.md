---
bump: minor
---

### Changed

- `book-distill`, `course-digest`, `docpage-digest`, `map-corpus` and `video-digest` have shorter descriptions, one trigger per use, measured against the old text by held-out trigger probes. `book-distill`, `docpage-digest`, `map-corpus` and `video-digest` also have tighter text in the body sections the new outcome cases reach, measured by those cases. `setup` has a one-line description; its body is unchanged.

### Added

- Eight outcome eval cases under `evals/` (two each for `book-distill`, `course-digest` and `video-digest`, one each for `docpage-digest` and `map-corpus`), and frozen trigger-probe sets for the five model-invoked skills under `probes/`.
