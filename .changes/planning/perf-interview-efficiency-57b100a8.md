---
bump: patch
---

### Changed

- **Cheaper interview runs.** The Step 1 survey and the engineering defaults (quality bar, consumer standards, the variation-intent question, quality requirements) move out of `context/loop.md` into a new `context/survey.md`, so a round that needs only them, or only the glossary fallback, reads a small file, and `loop.md` itself now comes back from one read instead of in ranges. SKILL.md's "Spoke paths" section moves to the top and gives the exact path of every linked file and of `round.sh`, `check-open-questions.sh`, `check-round-codes.sh` and `registry.mjs`, so a session reads them directly rather than listing or grepping the plugin, and reads each file once per session. What the interview asks and decides is unchanged.
