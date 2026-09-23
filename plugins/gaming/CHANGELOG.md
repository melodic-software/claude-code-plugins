# Changelog

All notable changes to the `gaming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-09-22

### Added

- `dlss5` action router (assess, apply, remove, status, tune, refetch) over the
  `Invoke-Dlss5Mod.ps1` script, and a `setup` skill with the uniform check/apply contract.
- `data_dir`, `runtime_dll` and `runtime_source` options. State lives in `data_dir`, outside the
  plugin data directory, so it survives uninstall.
