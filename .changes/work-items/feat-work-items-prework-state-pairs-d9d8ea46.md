---
bump: minor
---

### Changed

- `/work-items:work` investigate mode's marker comment now carries a desired-state/result-state pair: `<!-- work-items:investigation outcome=<outcome> desired=cause-named -->`. `outcome=` stays first, so readers that match the outcome keep working; a reader compares the two fields to tell finished pre-work from pre-work that needs a follow-up.
