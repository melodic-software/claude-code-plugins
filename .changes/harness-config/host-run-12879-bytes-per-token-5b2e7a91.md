---
bump: patch
---

### Fixed

- `audit-instructions` sizes lanes at 2.7 bytes per token, fitted to the tokenizer of current
  models, so a lane no longer holds more text than its token budget. Its pointer to the glossary
  entry for tokens is rechecked as of 2026-11-03.
