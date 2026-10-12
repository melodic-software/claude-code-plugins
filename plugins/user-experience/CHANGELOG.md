# Changelog

All notable changes to the `user-experience` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.4] - 2026-10-12

### Fixed

- Shared library comments that restated Claude Code hook and plugin behavior now point at the
  live docs sections, and the prerequisites probe no longer gives a wrong reason for always
  exiting 0.

## [0.1.3] - 2026-10-11

### Changed

- Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5, so a
  slow version or `system-lib` probe no longer false-fails; a hung one costs at most 20 seconds.
  No change to this plugin's own entries.

## [0.1.2] - 2026-10-11

### Changed

- `scripts/lib/yaml-subset.mjs` is now a generated copy of the shared `lib/yaml-subset.mjs`, and
  its tests moved to `lib/`. The parser returns the same results, and a line with a long run of
  quotes inside a plain value no longer takes quadratic time.

### Fixed

- An escaped `\"` or doubled `''` quote inside a flow-sequence item no longer ends the item, so
  `["a\",b", c]` parses as two items instead of splitting at the escaped quote.

## [0.1.1] - 2026-10-10

### Changed

- The `routing` and `detect` test suites declare the manifests and fixtures they read, so the
  pull-request test selection runs them when those files change. Nothing the plugin ships changes.

## [0.1.0] - 2026-10-09

### Added

- `shape` skill: the front door. It runs detect, states the app's stage with its signals, the
  audience, the project's own evidence and the team settings, then chains the job skills below in
  order through the Skill tool, asking for access it lacks.
- `plan-user-research` skill: research plans and instruments (discussion and facilitator guides,
  screeners, usability test scripts) in the shared deliverable envelope. It writes instruments
  only and never recruits or runs sessions.
- `synthesize` skill: themes as AI-suggested codes for a named analyst, proto-personas labeled as
  assumptions, and jobs to be done in the team's chosen school.
- `structure` skill: user flows and information architecture as mermaid flowcharts, journeys as
  tables.
- `evaluate` skill: evaluation plans, expert review, fair-choice checks and measure selection,
  with a fresh-context `evaluator` agent limited to Read, Grep and Glob.
- `setup` skill: checks and writes the team file `<home>/user-experience.yaml`.
- Reference files for research methods, synthesis, journeys, flows and IA, the discovery phase,
  evaluation, measurement, first run and AI features, plus `reference/deliverable.md`, the
  envelope every deliverable carries.
- `reference/routing.json` and its schema (group field `job`, nine jobs): this repository's
  skills, Anthropic design and product-management skills (unconfirmed) and account-bound research
  and analytics tools (deferred until install-tested).
- `scripts/detect.mjs`: project signals, installed routes (a generated copy of the shared
  `lib/installed.mjs`), and the team file read through one resolver, merged under two named
  policy rules, with path values kept inside the project and a missing or malformed file falling
  back to the built-in routes.
- Evals: 21 `claude plugin eval` cases, read-only.
