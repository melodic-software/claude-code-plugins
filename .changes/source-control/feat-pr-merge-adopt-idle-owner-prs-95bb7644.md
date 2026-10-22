---
bump: minor
---

### Added

- The pr-merge lane adopts an idle owner pull request (owner decision Q22): one an account in
  `adoption.owner-ids` (none when absent) opened, matched by account id, not a draft,
  whose update and head commit are both at least `adoption.idle-hours` old (read at main, 24
  when absent), and with no hold label or body hold. pr-merge.yml lists those accounts' PRs.
  The decision records it as `eligibility.adoption`; every other gate applies unchanged.
