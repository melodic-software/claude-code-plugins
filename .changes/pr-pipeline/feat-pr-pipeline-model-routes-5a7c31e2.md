---
bump: minor
---

### Added

- **Role profiles in `models`.** A profile may name a multi-agent role (`role`, optional `workload` and `effort-role`) in place of a model. resolve-config takes its model and effort from the base checkout's [multi-agent role map](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/multi-agent/reference/defaults.yaml). The model is `opus` when the role map gives `inherit`, `default`, a model ID or nothing. The schema refuses a `model` or `effort` key on a role profile, so it can name neither `default` nor a model ID.
- **fix-ci routes to a role profile:** a worker on code at the verifier's effort, with 75 turns as before.
- **New `applied-by-patch` output** from resolve-config: the activity that applies the selected activity's patch.
