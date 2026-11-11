---
bump: patch
---

### Changed

- Skill criteria and the model-adaptation contributor conventions follow upstream-drift 5.0.0: a
  pointer record is a section-anchored pointer with no as-of date or recheck trigger; only a
  stored value, such as one of our own measurements, keeps both. Existing stamps are unchanged.
- Skill criteria's History and provenance exemption matches `/skill-quality:check` check 29: a
  bare `#N` is exempt when its block also cites the same N upstream, and a stored-value record
  with an as-of date and recheck trigger stays exempt.
