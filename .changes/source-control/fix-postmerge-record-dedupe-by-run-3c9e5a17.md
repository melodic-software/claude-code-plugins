---
bump: patch
---

### Fixed

- `babysit_postmerge.py --remediate` comments on an existing demotion record that names the same failing
  run instead of filing a second one: `post-merge-demotion-alert.yml` keys its record on the run's head
  SHA and this check on the merge commit, so one red run could leave two records, both holding the gate.
- A red run that charges several lane merges files one record, not one per merge: the record lists every
  merge the run charges and asks a human to pick the one to revert. Any open record holds the gate for all.
- Its demotion record now says the unattended merge path stays at rung off while any demotion record is
  open: fix main first, then close every open record directly; a new sighting of the same failure reopens its record.
