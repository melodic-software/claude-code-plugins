# Changelog

All notable changes to the `event-storming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Added

- `--design-level` deep dive now guards its prerequisite: when no prior Process Modeling board exists for the bounded context in `${CLAUDE_PLUGIN_DATA}/history.jsonl`, it surfaces the missing prerequisite and offers to run `--process-model` first instead of fabricating a process model or aggregates. Pinned by the new `design-level-missing-prerequisite` eval.

### Fixed

- Dangling bare "memory" references in the simulation skill's deep-dive and evaluation steps now use the `${CLAUDE_PLUGIN_DATA}/history.jsonl` run-state seam like every sibling reference.
