---
bump: patch
---

### Fixed

- `audit` writes its findings file when it examined files and found nothing relay-eligible, with an empty `## Findings` section.
- `audit` names a detector finding's `rule` value in full in its report.
