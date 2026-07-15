# Changelog

All notable changes to the `codebase-audit` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Added

- Optional background/unattended execution variant for the Phase 1 per-file fan-out: the same
  discovery can run as a saved workflow (background execution, same-session resume, rerunnable
  script) when the environment provides such a surface; the in-session fan-out remains the default.
