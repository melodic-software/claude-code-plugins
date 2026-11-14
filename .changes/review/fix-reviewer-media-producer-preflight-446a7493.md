---
bump: patch
---

### Fixed

- `/review:reviewer-media` checks that `/explainer-video:produce` is loaded before it claims a
  pull request's head, on a direct run and on `--handoff`. Without it the build skips with reason
  `producer-unavailable` (`decide.mjs --producer-unavailable`), so no head is left claimed with
  nothing able to finish it. A missing `/speech:narrate` still builds captions-only and the
  report says narration is unavailable.
