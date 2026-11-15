---
bump: patch
---

### Changed

- The research deep-tier workflow runs its fetch stage, which only returns a script's output, on the retrieval role (Sonnet at medium effort by default) instead of the worker role, and asks the synthesizer for a short summary rather than a fixed sentence count.
- The explore, research and blindspot instructions drop capital-letter emphasis and fixed step or sentence counts, settle rules that disagreed between files, and correct stale section names and minimums.
