---
bump: patch
---

### Fixed

- A board write that fails no longer leaves a temp file beside the board, a temp file left by a killed run no longer blocks a later write, and rewriting a board keeps its file mode.
