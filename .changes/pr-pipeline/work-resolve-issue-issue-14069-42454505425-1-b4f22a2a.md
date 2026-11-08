---
bump: minor
---

### Added

- `models.issue-status` takes two optional keys. `hold-states` lists the states that hold an issue for a person (unset: needs-human, needs-owner-decision, needs-reporter-info, needs-spec). `ready-state` names the state that admits an issue to an autonomous lane, the one a bot-setters value never counts for (unset: agent-ready). The source-control babysit scripts and /work-items:morning-brief read both, and the work-items GitHub adapter's Work status trust reads `ready-state`. This repository's lane config reader does not read either key, so this repository leaves both unset.
