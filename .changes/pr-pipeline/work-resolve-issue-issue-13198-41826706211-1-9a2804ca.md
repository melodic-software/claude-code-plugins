---
bump: patch
---

### Changed

- The `resolve-conflicts` activity in `docs/conventions/pr-pipeline.yaml` and the
  `claude-code-plugins.yaml` example now runs `source-control:pull-request` with
  `args: conflicts --ci --unattended` in place of `source-control:resolve-conflicts` with
  `args: ci`. The activity keeps its name, so the grant files keyed on it are unchanged.
