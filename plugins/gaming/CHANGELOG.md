# Changelog

All notable changes to the `gaming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0] - 2026-09-23

### Added

- Per-game presets. Shipped presets live in `skills/dlss5/presets/<key>.json`; a local override
  with the same key in the data directory's `presets` folder wins per ini key. `assess` reports
  the matching preset (by Steam app id or exe name) with each key's source, and `apply -Preset
  <key>` writes its ini keys and records them in the manifest (`preset`, `iniEdits`).
- A preset may set only `Dx11Upscaler`, `RestoreComputeSignature` and `RestoreGraphicSignature`.
  `apply` refuses before any write on any other key, on `AutoCapture` whatever its value, on a
  value that is not a plain token, and on a malformed preset key. A preset key missing from the
  build's ini rolls the apply back.
- Shipped presets: `cyberpunk-2077` (proxy `dxgi.dll`, manual settings only) and `007-first-light`
  (`RestoreComputeSignature=true`, conditional per the wiki). Each carries its sources, as-of dates
  and a recheck trigger.
- `SKILL.md`: the apply confirmation lists the preset keys and their sources, apply and tune print
  the preset's manual settings as a setup guide, the ledger Notes record the preset, and a research
  step writes a local preset from trusted sources for a game with no shipped one.
- `reference/presets.md`: format, allow-list, merge rule and shipped presets.
- `candidate-selection.md`: SEO mod sites are listed as untrusted.

### Fixed

- `assess` and `apply` counted the mod's own upscaler copies (the fork's `OptiScaler\` folder
  ships FSR and XeSS DLLs) and listed duplicates. Files under the mod's folders and files this
  game's manifest names no longer count, and entries are unique by path.

### Changed

- `-RestoreComputeSignature` now targets `[Hotfix]`, the section both pinned builds use.

## [0.2.0] - 2026-09-23

### Added

- `assess` verdict `not-a-candidate`: the game tree holds no DLSS, FSR 2+ or XeSS DLL, so the mod
  has no upscaler to hook. `apply` refuses it before any write, like `unknown`; there is no
  override flag. The router tells the user the mod will not help and names the user-driven path
  (a wiki-listed upscaler mod, then `assess` again).
- `reference/candidate-selection.md`: requirements, the detected DLL names, non-candidates, engine
  notes, and trusted versus untrusted per-game config sources.
- `tuning-guide.md` troubleshooting row for NR that looks inert with a healthy log.

### Changed

- `assess` JSON: the `dlss` field is replaced by `upscalers`, one entry per DLSS, FSR or XeSS DLL
  with its `family`. It matches exact upscaler names, so frame generation, ray reconstruction and
  `nvngx_dlssnr.dll` no longer count.
- `upstream-watch.md` and `fork-comparison.md`: wilsjo2 `v0.8.91` is the newest prerelease,
  releases from `v0.8.5` ship `SHA256SUMS.txt`, and #56 is still open with no maintainer reply.
  The pins are unchanged.

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
