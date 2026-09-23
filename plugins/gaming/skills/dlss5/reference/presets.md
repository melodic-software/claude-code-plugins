# Presets

A preset is a per-game starting point: the `OptiScaler.ini` keys `apply` can set, and the in-game
settings it cannot. Its job is a game that looks right on first launch.

## Where presets live

| Kind | Path | Reviewed by |
|---|---|---|
| Shipped | `presets/<key>.json` in this skill | Pull request to this plugin |
| Local override | `presets/<key>.json` in the data directory | The user, on this machine |

`<key>` is lowercase letters, digits and hyphens, such as `cyberpunk-2077`. A local file with the
same key as a shipped one overrides it:

- **ini keys:** merged per key. The local value wins, and every key carries `source` `shipped` or
  `local` in the `assess` JSON, the `apply` output and the manifest.
- **manual, title, proxy, recheck:** the local field replaces the shipped one when present.
  `manualSource` names which one was used.
- **sources:** both lists are kept.

A local file with a new key is a preset of its own.

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

| Field | Meaning |
|---|---|
| `match` | `steamAppId` (from the Steam `appmanifest`), or an `exe` name present in the exe directory. `assess` reports the first match, local presets first |
| `proxy` | Optional. One of the four proxy names; the skill uses it when `assess` lists it as free |
| `ini` | Keys `apply -Preset` writes. Only the allow-list below is accepted |
| `manual` | In-game settings, printed after `apply` as the setup guide |
| `sources` | Every claim's source and the date it was read. Trusted sources only |
| `recheck` | What makes the preset stale; `refetch` checks it |

## ini allow-list

A preset may set only these keys. The section comes from the list, not the preset file. Both pinned
builds (Dagherbou `v0.2.0-patch1`, wilsjo2 `v0.8.3`) carry each key in that section.

| Key | Section |
|---|---|
| `Dx11Upscaler` | `Upscalers` |
| `RestoreComputeSignature` | `Hotfix` |
| `RestoreGraphicSignature` | `Hotfix` |

The script refuses, before any write:

- any other key, which keeps the baseline edits (`[DlssNr] Enabled`, `[Log]`) and every safety
  behavior out of a preset's reach;
- `AutoCapture` by name, whatever its value;
- a value that is not a plain token (letters, digits, `_`, `.`), so no value can carry a line
  break into the ini;
- a key that is missing from the build's `OptiScaler.ini`. The apply rolls back rather than
  record a setting that never landed.

`WhitePointSource` is not on the list: neither pinned build's ini has it. The White point choice
stays a manual setting.

Every applied key is in the manifest (`iniEdits` and `preset`). `OptiScaler.ini` is itself a
manifest file, so `remove` deletes it and the folder returns to its snapshot byte for byte.

## Shipped presets

| Key | ini | Standing |
|---|---|---|
| `cyberpunk-2077` | none | Proxy `dxgi.dll`; manual DLSS Quality over Auto, Output Scaling off, exposure scan off |
| `007-first-light` | `RestoreComputeSignature=true` | Conditional per the wiki: on NVIDIA it is needed when overriding sharpness, and the preset's manual steps use Sharpness Override. Path tracing and Ray Reconstruction off first is a precaution from one Linux report |

A preset ships only when every claim in it has a trusted source. Challenged claims never ship:
`WhitePointSource=0` as a fix for inert NR (reports conflict, see `tuning-guide.md`), and
`RestoreComputeSignature` as a Glacier 2 engine rule (only the 007 First Light page says it).

## Verification record

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Allow-listed keys and sections | `gh api` contents of `OptiScaler.ini` at Dagherbou `v0.2.0-patch1` and wilsjo2 `v0.8.3` | 2026-09-23 | A new pin |
| Shipped preset contents | Each file's `sources`, re-read on the date given there | 2026-09-23 | Each file's `recheck` |
