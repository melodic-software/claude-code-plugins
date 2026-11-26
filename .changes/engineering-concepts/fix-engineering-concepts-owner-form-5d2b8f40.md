---
bump: patch
---

### Fixed

- `scripts/lookup.mjs` now reports a record whose `owner` is neither an `https://` URL nor a skill name (`plugin:skill`, optionally with a leading `/`) as malformed, with its file and line, and skips it. The records check validates every record with the lookup's own rules (`parseRecord` and `recordLines`, now exported), so the two cannot disagree on which lines are valid or where a bad line is.
