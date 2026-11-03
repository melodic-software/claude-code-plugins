---
bump: patch
---

### Fixed

The update helper's `--apply` diff preview no longer shows `vendor/LICENSE` as wholly deleted. The upstream skill directory ships no LICENSE, so that hunk filled the 200-line preview and real changes never showed.
