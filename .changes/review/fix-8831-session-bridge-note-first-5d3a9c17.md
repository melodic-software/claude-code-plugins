---
bump: patch
---

### Fixed

- The view bridge's session bridge now writes the data-framing `note` ahead of `events` in each `/api/wait` answer and each channel relay `events` line. A model reading the line top to bottom now meets the instruction to treat page text as data before it meets the page text.
