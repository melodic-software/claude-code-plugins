---
bump: minor
---

### Added

- pull-request: `prep` runs a comment pass after simplify and before the simplify diff is
  reviewed, through `/code-tidying:remove-comments --pipeline --added-since <base>` when that
  plugin is enabled. An unattended run applies no comment edit unless the project's instructions
  pre-approve it: it runs the pass in `report` mode and lists the proposals in the prep report.
