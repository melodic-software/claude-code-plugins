# Changelog

All notable changes to the `user-experience` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-10-20

### Added

- `/user-experience:evaluate` expert review of a live app now runs three checks
  (`reference/evaluation.md` "Live-app checks"): the primary action and the thing asked about on
  screen without scrolling at a phone, a tablet and a desktop size; question, label and
  instruction copy that could point at more than one view, element or device; and in-product
  pictures compared with the live screen and theme, with natural against displayed size.
- Three evaluate eval cases, one per check.

- Shared `resolve-convention-home.sh` synced: `--ref` (a 40-hex commit id or `origin/<name>`) reads the pointer and the home as committed, `-` reads the region from stdin, a `declined` line in the region exits 4 so the caller does not ask again, and a root that is `$HOME`, an ancestor of it or outside a git work tree exits 5 (not applicable).

### Changed

- With no `--root`, `resolve-convention-home.sh` reads the git toplevel of `CLAUDE_PROJECT_DIR` (else of the current directory): one home per git root.
- `detect.mjs` reads no team file when the repository declined a convention home or none applies (the project is `$HOME`, an ancestor of it, or outside git): the built-in routes and defaults apply, and `skipped_reason` says why.

### Fixed

- Shared `prerequisites.mjs` synced: a `node-pkg` or `python-pkg` entry reads `CLAUDE_PLUGIN_DATA` only when its last path segment is this plugin's name or starts with `<plugin>-`, and treats a literal `${...}` value as unset, so another plugin's data directory reports `unverified` instead of `missing`. This plugin declares neither kind, so its behavior is unchanged.

- A `CLAUDE.md` symlinked to `AGENTS.md`, or the reverse, no longer prints a `duplicate:` notice.

## [0.1.8] - 2026-10-15

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook
  entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior
  is unchanged.

## [0.1.7] - 2026-10-13

### Fixed

- The shared prerequisites checker (`lib/prerequisites.mjs`) now finds a `python-pkg` in the
  plugin's own installed Python set: a module the interpreter cannot import on its own is looked
  up in the set a plugin with a committed `requirements.txt` installs into its data directory,
  instead of being reported missing. When the data directory is unknown, the entry reports
  `unverified`. This plugin declares no `python-pkg` entry, so its own checks are unchanged.

## [0.1.6] - 2026-10-12

### Fixed

- Shared library comments that restated Claude Code hook and plugin behavior now point at the
  live docs sections, and the prerequisites probe no longer gives a wrong reason for always
  exiting 0.

## [0.1.5] - 2026-10-11

### Changed

- The README points at the live subagent frontmatter section for the `evaluator` agent's pinned
  model, effort and turn cap, with an as-of date and recheck trigger.

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

- `shape` skill: the entry point. It runs detect, states the app's stage with its signals, the
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
