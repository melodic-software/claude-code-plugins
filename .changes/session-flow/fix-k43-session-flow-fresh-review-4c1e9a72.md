---
bump: patch
---

### Fixed

- `/session-flow:workflow` Stage 10 and pre-PR step 2 are done only after a fresh-context reviewer returns, with the self-review as the floor; under the `verification` levels `light` and `off` the self-review alone closes them and the report notes the skip. Stage 11 takes its outcome verdict from a fresh-context verifier.
- `/session-flow:retro` session mode under `retro_lenses: 1` reads the `verification` level: at `standard` and `strict` one fresh-context subagent runs the analysis and proposes the scores from the transcript, so the session no longer scores itself; at `light` and `off` it runs inline and notes the skip.
