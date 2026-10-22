---
bump: patch
---

### Fixed

- fix-docs is paused: its pr-unblock slot is `enabled: false`, so a dispatched run skips at
  resolve-config before any model turn, and the broker grants it nothing. Under run-claude-cli's
  subprocess env scrub the CLI forces the default permission mode instead of `auto`, so every
  fix-docs run failed its permission-mode check after spending a model leg
  ([run 39723040443](https://github.com/melodic-software/claude-code-plugins/actions/runs/39723040443)).
