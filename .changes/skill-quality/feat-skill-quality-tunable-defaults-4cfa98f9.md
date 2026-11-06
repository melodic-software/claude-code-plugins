---
bump: minor
---

### Added

- `measure-invocation.sh emit-plugin-eval` reads a `plugin_eval_runs` setting from `skill-quality.yaml` (then `skill-quality.local.yaml`) in the convention home for the runs per emitted case. The default stays 3, `--runs N` still beats the setting, and an INFO line names the resolved value and its layer.
