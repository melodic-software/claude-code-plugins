---
bump: minor
---

### Changed

- **Breaking: the `sync` skill is renamed `/dometrain:update`**, matching the `update` skills in
  `firecrawl` and `playbooks`. Its script now takes `--check` (the default, a read-only drift
  report) and `--apply` (refresh the vendored baseline), replacing the bare report mode and
  `--refresh-baseline`. `/dometrain:update --apply` runs the refresh from a working-tree checkout;
  it stays human-only (`disable-model-invocation`). Type `/dometrain:update` where you typed the
  old `sync` command.
