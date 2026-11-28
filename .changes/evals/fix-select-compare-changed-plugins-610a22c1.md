---
bump: patch
---

### Fixed

- `/evals:plugin-eval select` no longer puts a plugin's cases on the `cases:` line when the diff changes nothing under that plugin's `skills/`, `agents/`, `context/` or `evals/` (for example, a case whose grader reads another plugin's changed skill). A compare run refuses such a plugin, so those cases now print on a new `suite-only:` line, to run in a suite run on the default branch after merge. `agent-runs:` still counts them. The split applies only where the repository has `.github/scripts/plugin-eval/compare-arms.sh`.
