---
bump: patch
---

### Fixed

- The markdown-check git hook now fails, naming the tool and saying the change was not fully checked, when sed fails while it turns markdownlint's output into findings. A crashed sed used to leave no findings to block on and the commit passing.
