---
bump: patch
---

### Fixed

- `/harness-ops:observability items` no longer counts a message sent while a turn runs as a new turn: since Claude Code 2.1.325 such a message emits its own `user_prompt` event marked `delivery.mode` `mid_turn`, and the turn count now leaves those out (#16035).
