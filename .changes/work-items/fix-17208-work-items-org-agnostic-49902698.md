---
bump: minor
---

### Added

- configure lane workflows, the lane-record contract and the label-as-code owner

  /work-items:morning-brief reads its lane workflow list from the
  lane_workflows key under morning_brief: (the files the repo has); unset,
  the lanes are the workflows whose file uses a Claude action, and a file
  that cannot be read makes the Lanes section UNREADABLE. The
  lane_outcome_contract_ref key names where the lane-outcome record is
  documented and prints under the Lanes heading; unset, the skill lists
  the record fields the brief reads. label_as_code_repo in
  docs/conventions/work-items.yaml names the repository that owns the
  tracker's labels. The plugin no longer ships an organization's lane
  workflow list, lane-outcome links, label-as-code repository or account
  tool link; this repository sets its own values in
  docs/conventions/work-items.yaml.

### Fixed

- give label_as_code_repo a runnable read and name only its reader

  capability-tier-labels.md and the schema run parse-concern-value.sh from
  <plugin-root>, as ai-disclaimer.md does. The morning brief's record field
  list names v and the credential fields it reads.
