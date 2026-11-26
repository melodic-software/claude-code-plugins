---
bump: patch
---

### Fixed

- `scripts/lookup.mjs` now reports a record whose `owner` is neither an `https://` URL nor a skill name (`plugin:skill`, optionally with a leading `/`) as malformed, with its file and line, and skips it. The records check applies the same rule.
