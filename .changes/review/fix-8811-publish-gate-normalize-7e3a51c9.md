---
bump: patch
---

### Fixed

- The publish gate now catches a credential or machine path hidden by fullwidth look-alike characters, zero-width characters or soft hyphens, JSON `\uXXXX` escapes, nested tags or double-encoded entities, or a markdown backslash escape such as `\_`. A backslash before `/`, `.`, `"` or `'` is still read as written.
