---
bump: major
---

### Changed

- The lyric review and rewrite skill is invoked as `/songwriting:revise`, with no alias; `diagnose` stays its default action and changes nothing.
- Its per-skill verification level in `songwriting.yaml` is keyed `verification_skills.revise`; a `diagnose` key no longer applies.
