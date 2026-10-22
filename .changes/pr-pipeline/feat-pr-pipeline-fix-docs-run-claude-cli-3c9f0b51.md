---
bump: minor
---

### Added

- A skill activity's `permission-mode` (`dontAsk`, the default, or `auto`) sets the read
  runner's launcher mode, through `resolve-config`'s new `permission-mode` output. A step after
  each launcher leg fails the run unless the CLI's init message reports that mode. fix-docs sets
  `auto`
  ([ADR 0049](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)).
