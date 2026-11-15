---
bump: patch
---

`/evals:plugin-eval` no longer repeats a score, delta or interval from an INVALID run, not even while refusing it; it reports the INVALID line and its reasons and calls the figure "the delta in the noise report".
