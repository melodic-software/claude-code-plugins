---
bump: patch
---

### Changed

- The worker, verifier and retrieval defaults are rechecked against `CLAUDE_CODE_SUBAGENT_EFFORT` and the Opus 5.5 end-of-turn completion check, with no value changed. Their recheck conditions now fire when the docs say where that variable ranks, and the verifier's model reason records why a smaller completion-check model is not a verifier.
