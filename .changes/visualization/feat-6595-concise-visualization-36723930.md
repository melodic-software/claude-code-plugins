---
bump: patch
---

### Changed

- `present`: shorter description (407 characters, down from 498) with every trigger phrase kept; held-out trigger counts were unchanged on Opus and Sonnet. Both skill bodies and the `visualize` description are unchanged, because the shorter versions did not pass the eval measurement.
- Adds six regex-graded outcome eval cases under `evals/` and frozen trigger probes under `probes/`.
