---
bump: patch
---

### Added

- Frozen description-trigger probes for `check` and `narrate` under `probes/` ([#6592](https://github.com/melodic-software/claude-code-plugins/issues/6592)).

### Changed

- The `check` and `narrate` descriptions are shorter (426 to 367 and 768 to 629 characters), keeping every quoted trigger phrase and boundary. In held-out trigger probes on Opus, `check` fired on 24 of 24 positive runs before and after, with the same 12 of 24 negative runs quiet; `narrate` fired on 17 of 24 positive runs (16 of 24 before) and stayed quiet on 24 of 24 negative runs (22 of 24 before).
