---
bump: patch
---

### Fixed

- `babysit_postmerge.py --remediate` comments on an existing demotion record that names the same failing
  run instead of filing a second one: `post-merge-demotion-alert.yml` keys its record on the run's head
  SHA and this check on the merge commit, so one red run could leave two records, both holding the gate.
- Its demotion record now says the unattended merge path stays at rung off while any demotion record is
  open: fix main first, then close every open record directly, since a red main reopens them.
