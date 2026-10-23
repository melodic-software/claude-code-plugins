---
bump: minor
---

### Added

- `babysit_verify_evidence.py evidence --lane-link` first reads the pull request's issue link by the pr-merge lane's own rule (`babysit_merge_policy._linked_issue`: one closing issue in this repository, or, with none, the one issue its plain `Refs:` lines name) and adds `ineligible` to its line: null when the lane takes the link, else why not, with refusal `verify:ineligible` and no verdict or config read. A failed read refuses. The verdict read that follows takes the link read's pull request instead of reading it again.
