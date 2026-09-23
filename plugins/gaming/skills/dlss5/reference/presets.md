# Presets

A preset is a starting point for `OptiScaler.ini`: the keys `apply` can set, and the in-game
settings it cannot. Its job is a game that looks right on first launch, with the user's own
hotkeys.

## Layers

Four layers, lowest precedence first. Each is optional.

| Source | Path | Applies to | Reviewed by |
|---|---|---|---|
| `shipped-base` | `presets/_base.json` in this skill | Every game | Pull request to this plugin |
| `shipped` | `presets/<key>.json` in this skill | The game its `match` names | Pull request to this plugin |
| `local-base` | `presets/_base.json` in the data directory | Every game | The user, on this machine |
| `local` | `presets/<key>.json` in the data directory | The game its `match` names, or the same `<key>` as a shipped preset | The user, on this machine |

`<key>` is lowercase letters, digits and hyphens, such as `cyberpunk-2077`. The two bases apply on
every `apply`, with or without `-Preset`. So the user's local base beats a shipped per-game preset:
the user's own choices, such as hotkeys, win over the plugin's defaults for a title.

- **ini keys:** merged per key. The highest layer that sets a key wins, and every key carries its
  `source` (the first column) in the `assess` JSON, the apply confirmation, the `apply` output and
  the manifest.
- **title, proxy, manual, recheck:** the highest layer that has the field wins, even when it is
  empty, so a local `"manual": []` clears the shipped steps. `manualSource` names the layer.
- **sources:** every layer's list is kept.

`assess` reports the effective preset. With no per-game match, `preset.key` is null and `preset`
holds the bases alone.

The shipped base sets no key and binds no hotkey, so nothing in it can conflict with a game. Put
your hotkeys and picture defaults in the local base.

## Format

```json
{
  "title": "Cyberpunk 2077",
  "match": { "steamAppId": "1091500", "exe": ["Cyberpunk2077.exe"] },
  "proxy": "dxgi.dll",
  "ini": [{ "key": "RestoreComputeSignature", "value": "true", "why": "the source's wording, and any condition" }],
  "manual": ["In-game DLSS mode: Quality, not Auto"],
  "sources": [{ "url": "https://...", "asOf": "2026-09-23", "supports": "what this source backs" }],
  "recheck": "The event that makes this preset stale"
}
```

A base needs only `ini`: `{ "ini": [{ "key": "ToggleKey", "value": "0x7C" }] }`.

| Field | Meaning |
|---|---|
| `match` | Per-game only. `steamAppId` (from the Steam `appmanifest`), or an `exe` name present in the exe directory. `assess` reports the first match, local presets first |
| `proxy` | Optional. One of the four proxy names; the skill uses it when `assess` lists it as free |
| `ini` | Keys `apply` writes. Only the allow-list below is accepted |
| `manual` | In-game settings, printed after `apply` as the setup guide |
| `sources` | Every claim's source and the date it was read. Trusted sources only |
| `recheck` | What makes the preset stale; `refetch` checks it |

## ini allow-list

A preset may set only these keys. The section comes from the list, not the preset file. Both pinned
builds (Dagherbou `v0.2.0-patch1`, wilsjo2 `v0.8.3`) carry each key in that section.

<!-- spellchecker:off -->

| Key | Section | Value | Kind |
|---|---|---|---|
| `Dx11Upscaler` | `Upscalers` | plain token (letters, digits, `_`, `.`) | Compatibility |
| `RestoreComputeSignature` | `Hotfix` | `true`, `false`, `auto` | Compatibility |
| `RestoreGraphicSignature` | `Hotfix` | `true`, `false`, `auto` | Compatibility |
| `ShortcutKey` | `Menu` | VK code | Hotkey: open the overlay (default Insert, `0x2D`) |
| `FpsShortcutKey` | `Menu` | VK code | Hotkey: FPS overlay (default Page Up, `0x21`) |
| `FpsCycleShortcutKey` | `Menu` | VK code | Hotkey: cycle the FPS overlay type (default Page Down, `0x22`) |
| `FGShortcutKey` | `Menu` | VK code | Hotkey: frame generation on and off (default End, `0x23`) |
| `ToggleKey` | `DlssNr` | VK code | Hotkey: Neural Rendering on and off (unbound by default) |
| `Enabled` | `DlssNr` | `true`, `false`, `auto` | Picture: Neural Rendering on at launch. `apply` writes `true` unless a preset says otherwise |
| `TransferStrength` | `DlssNr` | number or `auto` | Picture |
| `ColourStrength` | `DlssNr` | number or `auto` | Picture |
| `WhitePointScale` | `DlssNr` | number or `auto` | Picture |
| `MaxRatio` | `DlssNr` | number or `auto` | Picture |
| `Intensity` | `DlssNr` | number or `auto` | Picture |
| `LocalStructure` | `DlssNr` | number or `auto` | Picture |
| `LocalTone` | `DlssNr` | number or `auto` | Picture |
| `SkinStructure` | `DlssNr` | number or `auto` | Picture |
| `AutoMask` | `DlssNr` | `true`, `false`, `auto` | Picture |
| `Preset` | `DlssNr` | whole number or `auto` | Picture: the model preset, applied at the next launch |
| `Style` | `DlssNr` | whole number or `auto` | Picture |

<!-- spellchecker:on -->

A number is `-?digits` with an optional decimal part, such as `0.8`, `-1.0` or `1.000000`, the form
the overlay's Save Settings writes.

A `[DlssNr]` key is on the list only when both builds' ini comment for it describes the picture
alone:

<!-- spellchecker:off -->

| Key | Both builds' ini comment |
|---|---|
| `TransferStrength` | "How far the frame moves toward the model's picture" |
| `ColourStrength` | "Whether the model's colour arrives with its light" |
| `WhitePointScale` | "Multiplies the white point above before the model sees the frame -- the paper-white control" |
| `MaxRatio` | "The most the pass may brighten any pixel, as a multiple of what it already was" |
| `Preset`, `Style`, `Intensity`, `LocalStructure`, `LocalTone`, `SkinStructure`, `AutoMask` | "Model controls" |

<!-- spellchecker:on -->

Kept off, with the ini's own reason:

- `WorkingScale`: "Cost falls with the square of this", so it changes performance, not only the
  picture.
- `ScalingDownscaler`: it matters only with `WorkingScale` above 1.0.
- `DebugView`: it replaces the picture with a diagnostic view.
- `AutoCapture`: "Writes matched before/after frames to a dlssnr-capture folder", into the game
  folder. `apply` always writes `false`.
- `[Log]` keys, every other section, and the keys only wilsjo2's ini has (`Passes`,
  `RunBeforeSR`, `SkinProtection` and the rest).

The script refuses, before any write:

- any other key;
- `AutoCapture` by name, whatever its value;
- a value that does not match its type, so no value can carry a line break into the ini;
- a merged preset that binds one VK code to two actions, whichever layers they came from. An unset
  or `auto` hotkey counts as its default from the table above, so `ToggleKey=0x2D` alone collides
  with the Insert menu key; set `ShortcutKey` to another key or `-1` to free it;
- a key that is missing from the build's `OptiScaler.ini`. The apply rolls back rather than
  record a setting that never landed.

`WhitePointSource` is not on the list: neither pinned build's ini has it. The White point choice
stays a manual setting.

Every applied key is in the manifest (`iniEdits` and `preset`, with each key's source).
`OptiScaler.ini` is itself a manifest file, so `remove` deletes it and the folder returns to its
snapshot byte for byte.

## Hotkeys

A VK code is `0x01` to `0xFE` in hex (either case: Save Settings writes `0x7c`), or `-1` for no
key, or `auto` for the fork's default. Decimal codes and key names such as `F13` are refused. The
codes are Microsoft's
[virtual-key codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes).

Recommended, as judgment: bind F13 to F24 (`0x7C` to `0x87`), because games rarely bind keys that
most keyboards lack. Reach them with a keyboard or mouse macro key, or a remapping tool. For
example, in the local base:

| Key | VK | Action |
|---|---|---|
| F13 | `0x7C` | `ToggleKey`: Neural Rendering on and off |
| F14 | `0x7D` | `ShortcutKey`: open the overlay |
| F15 | `0x7E` | `FpsShortcutKey`: FPS overlay |
| F16 | `0x7F` | `FGShortcutKey`: frame generation on and off |

```json
{ "ini": [
  { "key": "ToggleKey", "value": "0x7C" }, { "key": "ShortcutKey", "value": "0x7D" },
  { "key": "FpsShortcutKey", "value": "0x7E" }, { "key": "FGShortcutKey", "value": "0x7F" }
] }
```

A rebound `ShortcutKey` replaces Insert everywhere the skill says "overlay (Insert)".

## Capture

After tuning a game in the overlay and pressing Save Settings, `capture` saves the result as the
game's local per-game preset:

1. It reads the manifest, so the mod must be applied. What apply wrote is the build's stock
   `OptiScaler.ini` (from `builds\<build>`) with the manifest's `iniEdits` over it. When the <!-- portability-ok: Windows path, not a shell regex -->
   build's `.provisioned.json` tag no longer matches the manifest's `tag`, `capture` refuses: the
   new stock defaults would read as tuning.
2. It compares each key in the game's `OptiScaler.ini` to that, by value: `0x7c` equals `0x7C`,
   and `0.700000` equals `0.7`.
3. A changed key on the allow-list, with a valid value, goes into the local preset, with a `why` of
   `captured <date> from the overlay's Save Settings`. Keys already in that file stay unless
   recaptured.
4. Every other changed key is listed, not captured: keys off the allow-list, invalid values, and
   `AutoCapture`, with a reminder to set it back to `false`.

The preset key is the one the manifest recorded, else the game's `match`, else `-Preset <key>`
for a new file, which then matches on the Steam app id, else on the largest exe in the folder
alone (a shared helper such as a crash handler would match other games). `capture` prints that
exe name; check it. A `-Preset` that names
another game's preset is refused. `capture` reads the game folder and writes only
`presets\<key>.json` in the data directory. A base edited after the apply does not leak into the <!-- portability-ok: Windows path, not a shell regex -->
capture, because the comparison is against what the apply wrote.

## Community presets

The shipped per-game presets are the community channel. The plugin never fetches presets at
runtime; a preset reaches other users only by shipping in a release.

To contribute one, open an issue or pull request on this plugin's repository with the preset file
and its evidence: the game, build and driver it was tuned on, and sources for every claim. A
captured file has none of those by itself: its `why` says only that it was captured. It is reviewed
like any other change, and ships only under the rule below.

## Shipped presets

| Key | ini | Standing |
|---|---|---|
| `_base` | none | Binds no hotkey and sets no key |
| `cyberpunk-2077` | none | Proxy `dxgi.dll`; manual DLSS Quality over Auto, Output Scaling off, exposure scan off |
| `007-first-light` | `RestoreComputeSignature=true` | Conditional per the wiki: on NVIDIA it is needed when overriding sharpness, and the preset's manual steps use Sharpness Override. Path tracing and Ray Reconstruction off first is a precaution from one Linux report |

A preset ships only when every claim in it has a trusted source. Challenged claims never ship:
`WhitePointSource=0` as a fix for inert NR (reports conflict, see `tuning-guide.md`), and
`RestoreComputeSignature` as a Glacier 2 engine rule (only the 007 First Light page says it).

## Verification record

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Allow-listed keys, sections and ini comments | `gh api "repos/Dagherbou/OptiScaler_DLSSNR/contents/OptiScaler.ini?ref=v0.2.0-patch1"` ([file](https://github.com/Dagherbou/OptiScaler_DLSSNR/blob/v0.2.0-patch1/OptiScaler.ini)) and `gh api "repos/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/contents/OptiScaler.ini?ref=v0.8.3"` ([file](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/blob/v0.8.3/OptiScaler.ini)) | 2026-09-23 | A new pin |
| Save Settings writes a bound hotkey as `{:#x}` (`0x7c`), `-1` or `auto`, and a float through `std::to_string` (`1.000000`) | `OptiScaler/Config.cpp` at both pinned tags (`GetIntValue`, `GetFloatValue`, the `[Menu]` and `[DlssNr]` writes) | 2026-09-23 | A new pin |
| F13 to F24 are `0x7C` to `0x87`; `0xFE` is the last defined code | Microsoft's virtual-key codes page | 2026-09-23 | Never: the codes are fixed |
| Shipped preset contents | Each file's `sources`, re-read on the date given there | 2026-09-23 | Each file's `recheck` |
