# Changelog

All notable changes to the `playgrounds` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1]

### Changed

- **use:** the description names the tune-a-parameter-space intent once instead of four ways; the
  marketplace-fetch gotcha states its rule in the present tense.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1
  (docs/specs/prompt-audit-skills-2026-09.md).

## [0.1.0]

### Added

- **Initial release: the `/playgrounds:use` wrapper skill.** One-step access to the
  first-party `playground` plugin from `claude-plugins-official`: a provenance-based
  presence check (install record over description wording, with shadow detection),
  cross-plugin invocation of the upstream skill with visible degradation, install
  uplift backed by a declared cross-marketplace dependency, feature-detected delivery
  guidance for cloud and remote sessions, five field-tested prompt recipes plus a
  repo-native SKILL.md-review recipe, and commit-stamped consumer notes
  (`context/consumer-notes.md`). The wrapper generates nothing itself; the upstream
  skill owns generation.
