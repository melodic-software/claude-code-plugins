---
bump: patch
---

### Fixed

- **`fingerprint.mjs compare` measures JSON files.** Quote-stripping blanked every JSON string, because each is a paired `"` span, so a local JSON file shingled to almost nothing and the separation rule could not fire whatever its strings copied. A local JSON object or array is now measured by its string values (keys skipped), each decoded and quote-stripped on its own, with spans reporting the file line of the value's literal. Other input, including JSON that does not parse, takes the text path unchanged; the output names the path in `local_format`.
