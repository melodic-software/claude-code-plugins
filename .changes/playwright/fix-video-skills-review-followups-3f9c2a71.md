---
bump: patch
---

### Fixed

- **`/playwright:demo-video` keeps an in-place step's narration under its own caption.** When a step that stays on its page has an `outcome`, its step and results lines now end before the outcome caption replaces the step caption: the edit slows the typed results, or the cursor travel when there are none, until they fit. Before, the step's line could play more than a second into the outcome caption.
