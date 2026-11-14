---
bump: patch
---

### Changed

- At verification level `standard`, `script-the-deterministic-work` and `use-your-skills` now accept a review skill that runs in its own context, as well as a fresh-context subagent, as the confirmation of a clean audit; running the change's own code or tests, or re-reading it inline, does not count.
