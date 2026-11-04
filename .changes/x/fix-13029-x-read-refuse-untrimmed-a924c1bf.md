---
bump: patch
---

### Fixed

- `read` passes a URL found in fetched text through the gate exactly as written: up to the next whitespace, or to the matching close of a quote or Markdown link that opens right before it. A token the gate refuses stays refused, never trimmed into one that passes.
