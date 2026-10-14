---
bump: minor
---

### Changed

- The pr-merge lane gate considers only pull requests the lanes App opened (`not-lane-authored` otherwise), and reads the work class from the pull request's single closing issue, never from a label on the pull request. No closing issue, or more than one, refuses with `linked-issues:<n>`. A class label counts when the lanes App applied it, or a human in person with no issue body edit after it; any other label is `class-label-untrusted`.
