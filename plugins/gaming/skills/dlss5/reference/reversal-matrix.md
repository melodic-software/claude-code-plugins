# Reversal matrix

What `remove` deletes, what it keeps, and why the forks' own removal script is not used. This file
is the single source for byproduct classification: `IsByproduct` in `scripts/Invoke-Dlss5Mod.ps1`
matches the byproduct rows below exactly, and the selftest carries one case per row. A row changes
together with the function and its selftest case.

## How removal works

Before any copy, `apply` snapshots every file under the game directory (path, size, SHA-256). After
the copy it writes a manifest listing every file it placed. `remove` deletes what the manifest
names plus any known byproduct, removes mod directories left empty, then diffs the tree against the
snapshot. A clean diff deletes the manifest and keeps the snapshot.

## Manifest files: installed by `apply`, deleted by `remove`

| File | What it is |
|---|---|
| `<proxy>` (default `dxgi.dll`) | The fork's `OptiScaler.dll`, installed under the proxy name |
| `OptiScaler.ini` | Fork config, edited on install: `[DlssNr] Enabled=true`, `AutoCapture=false`; `[Log] LogToFile=true`, `LogLevel=2`; `RestoreComputeSignature=true` when requested |
| `OptiScaler\*` | The fork's support tree |
| `Licenses\*` | The fork's licence files |
| `nvngx.dll_dlssnr.dll` | Dagherbou build only: the forwarder the runtime's caller gate requires |
| `nvngx_dlssnr.dll` | A copy of the NVIDIA runtime DLL, one per game folder |

## Byproducts: written at runtime, deleted by `remove`

| Pattern | Written by | Source |
|---|---|---|
| `OptiScaler.log` | The fork, when `[Log] LogToFile=true`, which `apply` sets so the `DLSS-NR cost` lines prove the pass runs | Fork source, `OptiScaler.ini` `[Log]` block |
| `OptiScaler.asi` | Not placed by `apply`; listed because the fork's own removal script deletes it, so a fork variant can leave one | The deletion list of the fork's generated `Remove_OptiScaler.bat` |
| `dlssnr-capture\*` | `[DlssNr] AutoCapture`, or a user-created `dlssnr-capture.trigger` file; raw before/after frames, up to 8 pairs | Fork source: `Config.h` `DlssNrAutoCapture { true }`, `DlssNr_Dx12.cpp` capture directory |
| `OptiScalerProfiles\*` | wilsjo2's Profiles feature, which saves named settings beside the DLL | wilsjo2 v0.8.5 release notes |

## Mod directories removed when empty

`OptiScaler\`, `Licenses\`, `dlssnr-capture\` and `OptiScalerProfiles\` are deleted after the file
pass, but only when empty and only when the snapshot shows the directory did not exist before
install. A directory still holding an unknown file stays.

## Kept

| What | Why |
|---|---|
| Any added file that is neither a manifest file nor a byproduct | Not the mod's to delete. `remove` lists it under `kept (unknown, not ours)` and `status` tags it `unknown` |
| Every file in the snapshot | Pre-install game files are never touched |
| `snapshot.json` | Kept after removal as the record of the pre-install tree; the next `apply` takes a fresh one |

## Drift after removal

When a pre-install file is modified or missing after the file pass, `remove` keeps the manifest and
prints the drift with a pointer to Steam's "Verify integrity of game files". After a verify, run
`remove` again. When the drift is a game update that landed after `apply`, the snapshot is simply
older than the game: `remove -Finish` prints the drift and drops the manifest anyway. Use it only
on the user's explicit request after they have seen the drift.

An interrupted `apply` leaves `pending.json` listing its intended files; `status` and `remove`
treat it as the manifest, so `remove` rolls a half-finished install back.

## Why the forks' `Remove_OptiScaler.bat` is not used

- The fork's `setup_windows.bat` generates it at install time, and the plugin never runs that
  interactive installer, so the removal script never exists in a folder the plugin modded. Neither
  release zip ships it.
- Its deletion list covers `OptiScaler.log`, `OptiScaler.ini`, `OptiScaler.asi`, the identified
  proxy DLL, `Licenses\` and `OptiScaler\`. It leaves `dlssnr-capture\`, the `nvngx.dll_dlssnr.dll`
  forwarder, the `nvngx_dlssnr.dll` runtime copy and, for wilsjo2, `OptiScalerProfiles\` behind.
- It has no snapshot, so it cannot tell whether the folder ended up as it started.

Basis: the Dagherbou `v0.2.0-patch1` source tree (the installer's uninstaller block, `Config.h`,
`DlssNr_Dx12.cpp`), read 2026-09-20. Neither fork writes to the registry, `%LOCALAPPDATA%`,
`%APPDATA%` or `%ProgramData%`, so the game folder is the whole footprint. Recheck when either
pinned build changes: a new build can add a runtime write path, as wilsjo2's Profiles did.
