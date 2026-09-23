# Changelog

All notable changes to the `gaming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1] - 2026-09-23

### Changed

- The default `data_dir` is now `Documents\Gaming\dlss5`, so dlss5 state no longer claims the
  whole `Documents\Gaming` folder. When `data_dir` resolves to the default, the script refuses
  every verb but `refetch` and `selftest` while the legacy `Documents\Gaming\state\` has entries
  and the new default's `state\` has none, and `setup check` step 9 reports it as FAIL. Move `runtime\`, `state\`,
  `builds\`, `cache\` and `LEDGER.md` into `Documents\Gaming\dlss5`.

## [0.1.0] - 2026-09-22

### Added

- `dlss5` action router (assess, apply, remove, status, tune, refetch) over the
  `Invoke-Dlss5Mod.ps1` script, and a `setup` skill with the uniform check/apply contract.
- `data_dir`, `runtime_dll` and `runtime_source` options. State lives in `data_dir`, outside the
  plugin data directory, so it survives uninstall.
