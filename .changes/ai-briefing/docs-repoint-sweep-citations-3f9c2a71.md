---
bump: patch
---

### Changed

- The build pipeline reference lists `validate.js`'s gates itself, since the script no longer carries them in a header comment, and says which gates block (exit 1) and which only warn.
