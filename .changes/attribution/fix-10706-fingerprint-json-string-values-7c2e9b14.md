---
bump: patch
---

### Fixed

- `fingerprint.mjs compare` measures a local JSON object or array by its string values. It used to quote-strip every value away, so a copy in a JSON file could never fire. Now it fires, and its span reports the value's line in the file. Keys are not measured. Each value is stripped on its own, so an unclosed fence in one value no longer blanks the values after it, and a quoted excerpt inside a value still strips. Markdown, a bare JSON scalar and malformed JSON compare exactly as before.
