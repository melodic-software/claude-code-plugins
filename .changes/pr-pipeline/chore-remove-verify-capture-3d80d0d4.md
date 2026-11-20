---
bump: major
---

### Removed

- **Breaking:** `pr-pipeline.schema.json` no longer admits `merge.verify-capture`, and the config reader no longer admits the `verify-map` and `verify-capture` run routes, so a `pr-pipeline.yaml` that sets either fails validation; delete them. `pr-verify-capture.yml`, the pr-verify judges' capture find and download steps, and the `maintenance-verify-whole-map.yml` pass are gone ([#17281](https://github.com/melodic-software/claude-code-plugins/issues/17281)). Every verdict records `capture: no-app`, as a run with no app set did before.
