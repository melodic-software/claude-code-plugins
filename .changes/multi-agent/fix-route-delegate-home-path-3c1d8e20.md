---
bump: patch
---

### Fixed

- let route's `delegate` script accept the `~/` user-file path the route skill passes

  `delegate` refused `--user-file '~/.config/multi-agent/role-map.yaml'` as not absolute, so
  every auto-delegated brief failed. It now expands a leading `~/` to `HOME`, as the resolver does.
