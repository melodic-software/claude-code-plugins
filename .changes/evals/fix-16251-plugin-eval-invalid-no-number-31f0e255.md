---
bump: patch
---

### Fixed

- `/evals:plugin-eval` no longer repeats a score, delta or interval from an INVALID run, not even while refusing it; it reports the `verdict: INVALID` line and its reasons and refers to the delta as "the delta in the noise report", not by its value.
