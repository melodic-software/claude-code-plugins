---
bump: minor
---

### Added

- `/work-items:triage` reads the repository's glossary, the ADRs covering the item's area and its scope statement before it evaluates an item. It names which of them it found in a `Read first:` line (#11867).
- A `triage_outside_prs` repository setting in `docs/conventions/work-items.yaml`, default `false`, says whether the repository takes requests as pull requests from outside contributors (#11867).

### Changed

- With `triage_outside_prs` unset or `false`, the `/work-items:triage` attention view lists no pull requests and does not fetch them. A pull request named explicitly is still triaged (#11867).
