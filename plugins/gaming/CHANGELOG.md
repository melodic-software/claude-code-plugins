# Changelog

All notable changes to the `gaming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.0] - 2026-09-24

### Added

- `reset` verb: rewrites the game's `OptiScaler.ini` to the build's stock ini plus the manifest's
  recorded `iniEdits`, byte for byte what `apply` wrote, undoing the overlay's Save Settings
  without a remove and apply. It prints every value it discards and a token, and writes only with
  `-ConfirmReset <token>`, refusing when the file changed since that preview; the skill asks the
  user first. It updates the manifest's hash for the file, so
  `status` stays clean and `remove` stays byte-exact. It writes no other game file, and refuses a
  manifest without a completed apply, ownership of `OptiScaler.ini`, recorded ini edits or build
  tags, or whose build was re-provisioned since.
<!-- spellchecker:off -->
- Per-build preset allow-list. For `-Build wilsjo2` presets and `capture`: `Passes`,
  `Pass2`/`Pass3` `Preset`, `Style`, `Intensity`, `LocalStructure`, `LocalTone`, `SkinStructure`
  and `AutoMask`, `SkinProtection`, `SkinToneEnabled`, `SkinDetail`, `SkinColour`,
  `EnvironmentDetail`, `EnvironmentColour`, `RunBeforeSR`, `FinishedPicture`, `HdrTransfer`,
  `DeferredDLSS`, `PrivateUpscaler`, `ResidualAcrossRR`, `ResidualAcrossRRBlend` and `WorkingScale`,
  each typed from wilsjo2 `v0.8.3`'s `Config.cpp` reader. `apply` refuses such a key on another
  build before any write, naming the key and its layer. `AutoCapture` stays refused; `DebugView`,
  `ShowSkinMask` and `UnlockPasses` stay off the list.
<!-- spellchecker:on -->
- `status` and `assess` (`installedBuild`) report the manifest's build against its build's current
  pin: `installed build is older than the current pin` (tags compared as versions), `newer than`,
  `differs from` (same version, another hash), or `unknown, re-apply to record` for a manifest
  written before 0.5.0.
- `reference/upstream-watch.md`, Updating a pin: detect, record in an issue, pin by pull request,
  then roll out one game at a time after `/gaming:setup apply` re-provisions the build. A
  prerelease is never pinned without a live test.

### Changed

- The default build is wilsjo2 `v0.8.3`; Dagherbou `v0.2.0-patch1` is the fallback. From the
  owner's live A/B in Cyberpunk 2077 (RTX 5090, driver 616.92, 4K DLSS Quality): the same NR cost
  (median 7.42 ms against about 7.4 ms), the runtime loading through the NGX driver with no
  forwarder, a clean exit, and a better-looking picture by default. `Passes=2` measured 15.2 to
  15.5 ms. `/gaming:setup apply` provisions wilsjo2 first.
- `capture` no longer aborts when a captured hotkey binds the same key as another preset layer
  (#4424). It writes every other changed key and lists the conflicting one with both bindings,
  their layers, and the binding the preset keeps. `apply`'s duplicate-hotkey refusal is unchanged.

## [0.5.0] - 2026-09-23

### Added

- Base presets. `presets/_base.json` in the skill and `presets/_base.json` in the data directory
  apply to every game, with or without `-Preset`. Precedence, lowest first: shipped base, shipped
  per-game, local base, local per-game. Every ini key carries its source (`shipped-base`,
  `shipped`, `local-base`, `local`) in `assess`, the `apply` output and the manifest. The shipped
  base sets no key and binds no hotkey.
- Hotkeys in presets: `[Menu] ShortcutKey`, `FpsShortcutKey`, `FpsCycleShortcutKey`,
  `FGShortcutKey` and `[DlssNr] ToggleKey`, validated as a VK code `0x01` to `0xFE`, `-1` or
  `auto`. A merged preset that binds one code to two actions, counting each unset hotkey's
  default, is refused. `reference/presets.md` recommends F13 to F24 for the local base.
<!-- spellchecker:off -->
- Picture keys in presets, from `[DlssNr]`: `Enabled`, `TransferStrength`, `ColourStrength`,
  `WhitePointScale`, `MaxRatio`, `Intensity`, `LocalStructure`, `LocalTone`, `SkinStructure`,
  `AutoMask`, `Preset` and `Style`, each validated as a bool, number or whole number. `WorkingScale`,
  `ScalingDownscaler`, `DebugView` and `AutoCapture` stay off the list.
<!-- spellchecker:on -->
- `capture` verb: diffs the game's `OptiScaler.ini` against what `apply` wrote (the build's stock
  ini with the manifest's `iniEdits` over it), comparing values so Save Settings' `0x7c` and
  `1.000000` spellings are not changes. It merges changed allow-listed keys into the game's local
  per-game preset and lists every other changed key, `AutoCapture` with a reminder to set it back
  to `false`. It refuses when the build was re-provisioned since the apply (another tag or asset
  hash), and it never writes into the game folder.
- Community presets: shipped per-game presets are the community channel, contributed by issue or
  pull request with evidence. The plugin never fetches presets at runtime. The router suggests
  upstreaming a captured preset.

### Changed

- `assess` JSON: `preset` is present whenever a base preset exists, with `preset.key` null when no
  per-game preset matches. Apply with `-Preset` only when `preset.key` is set.
- The manifest records `tag` and `buildSha256`, the build's pinned release tag and asset hash,
  read from its `.provisioned.json`.
  The ledger's Build column is filled from it.

### Fixed

- `apply` left the manifest's build tag empty.
- The 0.4.0 entry omitted two `assess` JSON fields: `discoveryGaps` (what launcher discovery could
  not read, apart from the anti-cheat `unchecked` list) and `antiCheat.reviewId` (the id
  `-AntiCheatReviewId` must repeat).

## [0.4.0] - 2026-09-23

### Added

- Launcher discovery for Steam, Epic Games Launcher, EA app and legacy Origin, Battle.net, GOG
  Galaxy, Ubisoft Connect, and the Xbox app and Game Pass. A new read-only `discover` verb lists
  installed games per launcher, what it could not read, and runtime DLL candidates; `setup check`
  step 7 runs it. `assess` prints `launcher`, `launcherSource` and `gameName`. Locations are in
  the new `reference/launchers.md`.
- `assess` and `apply` read the anti-cheat sources themselves: the on-disk scan, AreWeAntiCheatYet
  `games.json` fetched live and pinned to the commit SHA it read (matched by Steam app id or by
  name with the ™, ® and ’ glyphs normalized; only a non-empty `anticheats` list counts), and for
  Steam the store page's anti-cheat section, read with the age-gate cookies. Battle.net titles are
  a signal on Blizzard EULA 1.C.i and 1.C.ii, quoted in full in `reference/anticheat-posture.md`.
  `assess` reports `antiCheat.status`: `signals`, `unknown`, or `none-disclosed` (Steam only).
- Xbox app: `apply` refuses a `WindowsApps` path before any write, and every `apply` runs a write
  probe before the snapshot.

### Changed

- Anti-cheat is now a refusal by default with a typed at-own-risk acknowledgement, replacing the
  absolute refusal. `apply` refuses on any signal or an `unknown` status unless
  `-AcceptAntiCheatRisk` matches the game name, with `-AntiCheatResearch`, `-AntiCheatSources`,
  and `-AntiCheatReviewId`, which binds the acknowledgement to the game, status, signals and
  unchecked sources the user reviewed; any change after the review refuses.
  The router shows every signal and unchecked source and runs live ban and block research before
  it asks. The manifest records the acknowledgement, the signals, the research and its sources,
  and the AreWeAntiCheatYet commit; the ledger row repeats them. The plugin never disables,
  bypasses or tampers with an anti-cheat.
- A missing Steam anti-cheat section no longer clears a game by itself. It means only that no
  kernel anti-cheat was disclosed. The status is `none-disclosed` only with nothing on disk and an
  AreWeAntiCheatYet entry under the game's Steam app id that lists no anti-cheat. A title with no
  AreWeAntiCheatYet entry, or a fetch failure, is `unknown`.
- `assess` JSON: `requiresWebCheck` is replaced by `antiCheat` and `acknowledgementRequired`.
  `verdict` `refused` now means only a `WindowsApps` path.
- `provision -Runtime` scans every discovered game's install folder, not only Steam libraries.

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
