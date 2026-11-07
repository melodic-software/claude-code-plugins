---
bump: patch
---

### Fixed

- `/work-items:triage` now states in SKILL.md that the objection-window comment opens with the `<!-- work-items:objection-window until=<UTC> -->` marker the admission gate reads, then `Objection window until <UTC>.`, and that a report of the run quotes both lines. Runs that never opened `context/apply-outcome.md` summarized the comment and dropped the marker ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
