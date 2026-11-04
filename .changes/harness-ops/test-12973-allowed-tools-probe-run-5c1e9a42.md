---
bump: patch
---

### Changed

- `behavior-probes` records the first live run of `plugin-eval/unlisted-tools-offered` as record 21 ([#12973](https://github.com/melodic-software/claude-code-plugins/issues/12973)): on Claude Code 2.1.318 an eval case whose `allowed_tools` is `[Read, Glob, Grep]` is still offered `Skill`, `Task`, `TaskStop` and `ToolSearch`, and its `Skill`, `Task` and `ToolSearch` calls run, which contradicts the plugin-evals Grant tools section; the record holds an upstream report candidate for the owner.
- `behavior-probes` no longer says plugin eval runs remove every ungranted tool: write tools stay withheld until `--allow-tools` grants them, and record 21 shows the unlisted tools a case is still offered.

### Fixed

- The `plugin-eval/unlisted-tools-offered` checker removes its temp directory under `HOME` after the nested eval, including the directories `--keep-temp` leaves at mode 000, instead of leaving one behind on every run.
