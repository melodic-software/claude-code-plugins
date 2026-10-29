---
bump: minor
---

### Changed

- **`audit` runs without a config** ([#8766](https://github.com/melodic-software/claude-code-plugins/issues/8766)). Phase 0 first reads the config layers that `setup` lists, merges them, and names the layer behind each value on a new `Config:` line in the scope report. With no layer present it no longer refuses. It falls back to `tool: manual`, takes the diff target from `origin/HEAD`, mutates the changed source files minus test code (every source file under `--exercised`), and applies the effort mutant cap. It lists those defaults under `no config: fallback defaults`. The test command is never guessed: the user supplies or confirms it before the baseline run, and an unattended run with none stops and asks for one. When the configured tool is missing, the audit names the install command and offers `tool: manual` for the run. It refuses only when the user declines both.
- **`setup check` reports missing config as INFO** that names the audit's fallback, not FAIL, skips the tracked-file probe for a file that does not exist, and `setup` now calls configuration optional. `setup apply` still writes only the team file. New eval cases cover the fallback, the confirmed test command, a config at the user-global layer only, a missing tool, and the INFO probe.
