---
outcome: early-exit
tier: B
reason: plugin shape, skill topology, userConfig surface and storage root are all settled in the handoff's "Decisions already settled"; only the on-disk record shapes needed sketching
---

## Why this is an early exit

The design space this work would otherwise explore is already closed by the handoff
`.work/handoffs/20260921T045656Z-handoff-dlss5-plugin.md`, section "Decisions already settled".
Each bullet below is a [h1] decision recorded there with its basis, so there is no open design
thread to run:

- Plugin root is `gaming`, category `personal`, `defaultEnabled: false`, Windows-only declared in
  the README the way `plugins/kindle-dedrm` does. Forecloses per-verb top-level skills and a new
  taxonomy category.
- One router skill `gaming:dlss5` with actions assess/apply/remove/status/tune/refetch, plus
  `gaming:setup` with the uniform check/apply contract. Forecloses five physical skill
  directories.
- The script is invoked directly as `pwsh -NoProfile -File .../Invoke-Dlss5Mod.ps1`, the
  machine-health pattern, with no bash wrapper.
- `userConfig` carries `data_dir`, `runtime_dll` and `runtime_source`; ledger, snapshots,
  manifests and the runtime DLL all live under `data_dir`. `provision -Runtime` fills
  `runtime\` from the configured path, a local scan of installed games, or `runtime_source`.
- Uninstall is a manifest diff against a pre-install snapshot, not the mod's generated
  `Remove_OptiScaler.bat`.

What remains is a port plus one new verb, which is implementation shaping rather than design
exploration. Tier B rather than C because the on-disk records do change shape when the data
directory and the DLL path become parameters, so the record sketch below is the design artifact
this exit owes.

## Type sketch of the on-disk records

### Today, in `.work/dlss5/tool/game-mod.ps1`

Everything is rooted at `$PSScriptRoot`, the directory holding the script:

```
<script dir>\
  game-mod.ps1
  runtime\nvngx_dlssnr.dll          $Model, hash-checked against $ModelHash
  state\<GameKey>\snapshot.json
  state\<GameKey>\manifest.json
  LEDGER.md                          maintained by hand, not by the script
```

`<GameKey>` is computed in `StateDir`: the segment after `steamapps\common\` when the game
directory matches that pattern, otherwise the leaf directory name, with every character outside
`A-Za-z0-9_-` replaced by `_`. That key collides: off Steam, two installs whose exe directories
are both named `Win64` map to one state directory, and a game whose launcher and renderer live in
two exe directories maps both onto one. The parameterized form below fixes it.

`snapshot.json` is a JSON array, one object per file in the pre-install tree, sorted by path:

```jsonc
[ { "Path": "007FirstLight.exe", "Length": 64318856, "Sha256": "8ED4E86A…" } ]
```

`manifest.json` is a single object describing one apply:

```jsonc
{
  "build": "dagherbou",              // key into the $Builds table
  "proxy": "dxgi.dll",               // name OptiScaler.dll was renamed to
  "applied": "2026-09-20T22:24:24.5580788-04:00",
  "driver": "616.92",                // nvidia-smi at apply time, or "unknown"
  "restoreComputeSignature": true,
  "files": [ { "Path": "dxgi.dll", "Sha256": "114A1D18…" } ]   // every file copied in
}
```

`LEDGER.md` is two markdown tables. The game table has fourteen columns: Game, Exe dir,
Anti-cheat, Build, Proxy, ini deltas, Driver, DLL, Applied, FPS before, FPS after, Visual verdict,
Crashes, Notes. The Upstream watch table has four: Item, Known version, Checked, How to recheck.
There is no refetch cache; the recheck commands are run by hand.

The classification vocabulary that `status` and `remove` share lives in `Get-Stat` and
`IsByproduct`. An added file is `manifest` when the manifest names it, `byproduct` when it is
`OptiScaler.log` or sits under `dlssnr-capture\` or `OptiScalerProfiles\`, and `unknown`
otherwise. `remove` deletes only the first two classes and keeps every `unknown` file.

### Parameterized, under `plugins/gaming`

The record contents do not change. Their root does, and one new record appears:

```
<DataDir>\                           -DataDir parameter, default GetFolderPath('MyDocuments')\Gaming
  LEDGER.md                          same two tables
  runtime\nvngx_dlssnr.dll           default location for -RuntimeDll
  runtime\.provisioned.json          new: winning source, path or query-stripped URL, hash, timestamp
  builds\<build>\                    extracted fork release, replaces the $Builds Src paths
  builds\<build>\.provisioned.json   new: tag, asset, URL, verified hash, timestamp
  state\<GameKey>\snapshot.json      one new field
  state\<GameKey>\manifest.json      one new field, plus an optional observed-runtime hash
  state\<GameKey>\pending.json       new: in-flight apply, deleted on success
  cache\upstream.json                new: refetch's raw findings
```

`<GameKey>` keeps its existing prefix (the `steamapps\common\` segment when present, the leaf name
otherwise) and gains a `_<first 8 hex of the SHA-256 of the lowercased full path>` suffix, so
`Cyberpunk_2077` becomes `Cyberpunk_2077_3f9a1c08`. The suffix makes the key injective over
directories rather than over directory names; the prefix keeps the directory identifiable to a
human browsing `<DataDir>\state\`.

Consequences for the records themselves:

1. `snapshot.json` and `manifest.json` each gain one field, `gameDir`, holding the resolved
   absolute directory the record describes. Every verb re-checks it, so a record found under a key
   that no longer matches its directory refuses rather than restoring the wrong tree. The
   per-file array shapes are unchanged, but the DIRECTORY NAMES change, because the key gains a
   path-hash suffix. So the seven per-game state directories already on the proving-ground machine
   migrate by copying the tree, renaming each directory to its new key, and adding `gameDir` to
   both records. Not a no-op, and not a converter either. The migration itself is out of scope by
   the Brief.
2. `manifest.json` gains no path field beyond `gameDir`. The DLL path and data directory are
   inputs, not results. It does gain an optional `runtimeHash` recording the observed
   `nvngx_dlssnr.dll` hash when `-AllowUnknownRuntime` was used, because in that one case the
   pinned constant no longer identifies what was installed.
3. `pending.json` is the in-flight record. `Do-Apply` writes it before the first copy, listing
   intended destinations, and appends each as it lands. On success it is deleted and the manifest
   takes over; on a throw the catch deletes exactly what it copied. `remove` and `status` treat a
   leftover `pending.json` as a manifest, so a crash mid-copy stays reversible.
4. `builds\<build>\.provisioned.json` is what lets `setup check` tell a never-provisioned tree
   (INFO) from a provisioned-then-emptied one (FAIL). Without it the check has to guess, and the
   two states need opposite remediation prose.
5. `cache\upstream.json` holds what `refetch` read, so the model can diff it against the Upstream
   watch table without re-fetching. It MERGES: an item that fails to resolve keeps its previous
   `found` and `Checked` values and carries the new `error` beside them, so one offline run does
   not erase the baseline every later diff depends on:

```jsonc
{
  "checked": "2026-09-21T04:56:56Z",
  "items": [
    { "item": "Dagherbou/OptiScaler_DLSSNR", "found": "v0.2.0-patch1", "source": "gh api" },
    { "item": "GeForce driver", "found": "616.92", "source": "nvidia-smi" }
  ]
}
```

It is a cache in the strict sense: deleting it loses nothing that a re-run cannot recover, which
is why it is safe to keep it under `data_dir` rather than inventing a second root.

### The `assess` record

`assess` writes nothing. It is a read-only probe that returns a shape for the skill to render:

```jsonc
{
  "gameDir": "…\\bin\\x64",
  "gameRoot": "…\\steamapps\\common\\Cyberpunk 2077",  // where the anti-cheat scan ran
  "gameKey": "x64_3f9a1c08",
  "verdict": "eligible",            // eligible | refused | unknown
  "requiresWebCheck": true,         // clears only once the Steam anticheat_section is read
  "refusals": ["anti-cheat on disk: EasyAntiCheat\\"],
  "dlss": [ { "file": "nvngx_dlss.dll", "version": "310.3.0.0" } ],
  "dx12": true,
  "proxyCollisions": ["dbghelp.dll"],
  "steamAppId": "1091500"
}
```

`gameRoot` is separate from `gameDir` because the anti-cheat scan runs from the game root, not the
exe directory: `EasyAntiCheat\` is installed beside the root while the executable sits two or
three levels below it, so a scan rooted at `gameDir` returns clean on exactly the titles the
refusal exists for. The root is the `steamapps\common\<X>` segment when the path has one, and
otherwise the nearest of up to four ancestors.

`requiresWebCheck` exists because on-disk absence is not absence. Server-side and
launcher-delivered anti-cheat leave nothing in the install tree, so `eligible` from a file scan
alone is a provisional verdict and the router must not act on it.

Keeping it write-free is what lets `assess` run against a game the user has not decided about
without leaving a state directory behind.
