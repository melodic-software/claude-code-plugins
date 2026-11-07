---
bump: minor
---

### Added

- In a repository whose pipeline file sets `models.issue-status`, the pr-merge lane also refuses a lane pull request whose linked issue's Work status field holds a person's state (needs-human, needs-owner-decision, needs-reporter-info, needs-spec) that a listed human, the lanes App or a trusted bot setter chose, as `closing-issue-held:<state>`, at eligibility and again before the enqueue. A field it cannot read, or a malformed block, refuses as `closing-issue-status-unreadable`, so an organization without issue fields holds every lane pull request once the block is set. A repository without the block reads labels alone, as before.
- The capped close reads the same field, and parking an issue also sets its Work status to `confirmed`. A post-merge demotion record in such a repository is filed without the human-gated label and its Work status set to `needs-human`; when that write fails or GitHub keeps another option, the label is added instead and the run reports the error.
