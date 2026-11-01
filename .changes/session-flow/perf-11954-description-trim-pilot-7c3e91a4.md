---
bump: patch
---

### Changed

- Sixteen skill descriptions are trimmed to the description standard (one what-sentence, `Use when`
  with at most three quoted triggers, about 250 characters), from 7,877 to 4,153 characters in
  total. `check`, `setup` and `tidy-work` are unchanged. Live invocation probes on the plugin's own
  probe set, before and after, decide whether the trim ships.
