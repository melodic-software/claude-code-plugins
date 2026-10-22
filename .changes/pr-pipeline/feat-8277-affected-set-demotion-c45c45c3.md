---
bump: minor
---

### Added

- `merge.quarantine-days` (default 7): days a quarantine issue excuses its suite's out-of-set
  failures from post-merge demotion. post-merge-demotion-alert.yml now checks out main's tip and,
  when every newly failing suite is outside the merges' affected set, files no demotion record and
  runs no red-main report; it files or comments each suite's quarantine issue instead.
