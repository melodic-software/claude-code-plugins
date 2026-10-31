---
bump: patch
---

### Fixed

- The publish gate now catches a credential or machine path hidden by fullwidth look-alike characters, zero-width characters or soft hyphens, JSON `\uXXXX` escapes, nested tags or double-encoded entities, or a markdown backslash escape such as `\_`. A backslash before `/`, `.`, `"` or `'` is still read as written. The lanes' leak scan now also reads each file as UTF-8, so a credential hidden by a zero-width character, a soft hyphen or a fullwidth look-alike blocks there too.
