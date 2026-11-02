---
bump: minor
---

### Changed

- **The team config moves to `docs/conventions/mutation-testing.yaml`** ([#12290](https://github.com/melodic-software/claude-code-plugins/issues/12290)). It is a plain YAML file, validated by the new `schemas/mutation-testing.schema.json`, and keeps every key name of the setup template (`tool`, `command`, `diff-target`, `mutate`, `operators`, `timeout-ms`, `baseline-suite-ms`, `max-mutants`, `test-command`). For one release, the older `.claude/mutation-testing.md` is still read as the team layer while the YAML file is absent. `/mutation-testing:setup apply` writes the YAML file, and on its first write carries every key of the older file over unchanged. The local overlay `.claude/mutation-testing.local.md` and the arid-node record `.claude/mutation-testing-arid.md` keep their places.
