---
bump: patch
---

### Changed

- `/evals:plugin-eval select` counts a meaning-flipping word (`not`, `never`, `no`, `only`, `except`, `unless` and their contractions) inserted into an existing instruction line as a cut, so it runs the affected cases; other added words still run nothing.
