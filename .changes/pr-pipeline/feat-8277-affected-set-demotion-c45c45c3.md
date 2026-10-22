---
bump: minor
---

### Added

- `merge.quarantine-days` (default 7): days a quarantine issue excuses its suite from post-merge
  demotion. post-merge-demotion-alert.yml now checks out main's tip and files no demotion record
  when every newly failing suite is outside the merges' affected set or quarantined; it files or
  comments each suite's quarantine issue instead.
