---
bump: minor
---

### Added

- `standards_repo` in `<home>/plugin-quality.yaml` (`owner/repo`) names the shared standards repository the auditor checks a component against when a local checkout of it exists. Unset, no standards repository resolves; the auditor no longer looks for one organization's standards checkout.
