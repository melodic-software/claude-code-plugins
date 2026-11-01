---
bump: minor
---

### Added

- `dossier_branch_prefix`, a team setting in `docs/conventions/source-control.yaml` with default
  `dossier/`: the prefix of an owning work item's dossier branch, `dossier/<key>-<slug>`, one per
  owning item. `parse-branch-issue.test.sh` now checks that a `dossier/<N>-<slug>` branch yields
  `<N>`.
