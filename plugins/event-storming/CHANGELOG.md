# Changelog

All notable changes to the `event-storming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.4]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/domain-driven-design:curate-language`); behavior unchanged.

## [0.5.3]

### Changed

- Simulation session teardown is phrased shell-agnostically at both sites
  (`rm -rf` on POSIX/Git Bash, `Remove-Item -Recurse -Force` on PowerShell)
  instead of an unconditional `rm -rf` with no Windows path — cross-platform
  declaration wave.

## [0.5.2]

### Changed

- Soft references to the moved vocabulary skill now invoke `/domain-driven-design:curate-language` (was `/planning:domain-modeling`). Version bumped so existing installs receive the retargeted references.

## [0.5.1]

### Changed

- Workshop and simulation glossary graduation now delegates to `/planning:domain-modeling` when that
  skill is available. The standalone fallback remains discovery-first and lazy, and the boundary is
  explicit: glossary maintenance consumes already-established contexts and never performs context
  discovery.

## [0.5.0]

### Added

- Workshop wrap-up points now offer resolved domain terms for graduation into the consumer repo's committed project glossary instead of leaving them session-scoped: one entry per term with a 1–2 sentence definition and a plain `Avoid:` line of rejected synonyms, project-context terms only, created lazily when the repo keeps no glossary (repo root, or per-context files plus a root map). When the `planning` plugin is installed, `/planning:design` owns the format. Landed at Big Picture Wrapping Up, Design-Level Wrap Up, the Ubiquitous Language notation and simulation capture points, and a canonical graduation section in the methodology glossary reference.

## [0.4.0]

### Added

- `--discover-bcs` eval + fixture for the offline/exported-board path: a completed Big Picture board's items supplied directly as an export (`evals/fixtures/big-picture-board-export.md`) run through Bounded Context Discovery mechanically, without requiring a Miro connection. Distinct from the existing board-URL scenario, which still requires Miro to read a live board.

## [0.3.0]

### Added

- `--design-level` deep dive now guards its prerequisite: when no prior Process Modeling board exists for the bounded context in `${CLAUDE_PLUGIN_DATA}/history.jsonl`, it surfaces the missing prerequisite and offers to run `--process-model` first instead of fabricating a process model or aggregates. Pinned by the new `design-level-missing-prerequisite` eval.

### Fixed

- Dangling bare "memory" references in the simulation skill's deep-dive and evaluation steps now use the `${CLAUDE_PLUGIN_DATA}/history.jsonl` run-state seam like every sibling reference.
