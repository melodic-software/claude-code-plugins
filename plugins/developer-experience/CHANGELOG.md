# Changelog

All notable changes to the `developer-experience` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.2] - 2026-10-12

### Changed

- `setup`, `build-cli` and `audit-tools` point at the live Claude Code docs sections they rely on by anchor, each with an as-of date and recheck trigger.

## [0.1.1] - 2026-10-11

### Fixed

- `build-cli`'s CLI contract cites clig.dev's Philosophy "Robustness" section by its live anchor, `#robustness-principle`; the old `#robustness` anchor matched no section.

## [0.1.0] - 2026-10-08

### Added

- `setup`, a user-invoked skill that records a repository's developer tooling conventions as current fact and adds one pointer line to `AGENTS.md`; `check` reports drift and `apply` converges.
- `build-cli`, a skill for building, extending, porting or reviewing a team's command-line tools and scripts against a CLI contract.
- `audit-tools`, a read-only inventory of a repository's scripts, command-line tools, skills, hooks, subagents and MCP configs, with findings.
- `pointer-line.sh`, the helper `setup` uses to check or write its one line in the shared `plugin-conventions` block of `AGENTS.md` without touching any other line.
- A shared copy of the recommendation-basis contract, so each recommendation carries a `Basis:` line or is withheld as an open question.
