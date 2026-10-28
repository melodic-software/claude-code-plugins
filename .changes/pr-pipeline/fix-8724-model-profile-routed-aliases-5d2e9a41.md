---
bump: major
---

### Changed

- **Breaking:** `pr-pipeline.schema.json` no longer admits `default` for a profile's `model`, so a `pr-pipeline.yaml` that names it fails validation; name `opus` instead ([#8724](https://github.com/melodic-software/claude-code-plugins/issues/8724)). `default` passed no `--model`, which run-claude-cli cannot pass. `fable` and `best` stay refused for `model` and `subagent-model`. resolve-config now resolves a model profile's `model` and `subagent-model` outside `haiku`, `sonnet` and `opus` to `opus`, as it does for a role profile, so a config that skipped the schema check still never runs `default` or the frontier tier; `inherit` still sets no subagent model. The built-in `standard` profile, this repository's `standard` profile and the example config's now name `opus`.
