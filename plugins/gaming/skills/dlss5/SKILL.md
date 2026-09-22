---
description: "Apply, track, tune, and remove the community DLSS 5 Neural Rendering mod (OptiScaler forks) in a PC game on Windows. Action router: assess (on-disk eligibility plus the Steam anti-cheat check), apply (snapshot, then install), remove (byte-exact uninstall from the manifest), status (drift against the manifest), tune (in-game overlay guidance), refetch (fork, driver and runtime release watch). Use when: 'apply DLSS 5 to this game', 'is this game safe for the DLSS 5 mod', 'remove the DLSS 5 mod', 'check for new OptiScaler DLSSNR releases', or DLSS 5, DLSSNR, or OptiScaler is mentioned with a game folder."
argument-hint: "[assess|apply|remove|status|tune|refetch] [<game-dir>]"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Route a DLSS 5 mod request to one action. `scripts/Invoke-Dlss5Mod.ps1` does the on-disk work:
eligibility probes, snapshot, install, drift report, byte-exact removal. This skill does what the
script cannot: the Steam anti-cheat check, the user's confirmation, the ledger rows, and tuning.

Windows only, PowerShell 7. Run `/gaming:setup` first: `apply` needs a provisioned fork build and
a runtime DLL under the data directory, and this skill never acquires either.

## Resolving paths (do this first)

Resolve each option here, before composing any command, so the command line carries a literal path
or nothing.

| Parameter | Resolution |
|---|---|
| **Data directory** (`-DataDir`) | `${user_config.data_dir}` when set to a non-empty path. If it is empty or still shows an unexpanded `${user_config.data_dir}` token (option unset), omit `-DataDir`: the script defaults to `Gaming` under the user's Documents folder and follows a OneDrive-redirected Documents, which a hand-built path does not |
| **Runtime DLL** (`-RuntimeDll`) | `${user_config.runtime_dll}` when set to a non-empty path. If it is empty or still an unexpanded token, omit `-RuntimeDll`: the script defaults to `runtime\nvngx_dlssnr.dll` under the data directory |

Never type an option token onto a command line. An unset option survives substitution as its own
token, and Bash rejects it as a bad substitution before the script starts.

When the ledger path is needed and the data directory option is unset, get the default from the
native side: `pwsh -NoProfile -Command "Join-Path ([Environment]::GetFolderPath('MyDocuments')) Gaming"`.

## Running the script

```bash
pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1" -Verb assess '<game-dir>' -DataDir '<data-dir>' -RuntimeDll '<runtime-dll>'
```

- `<game-dir>` is the directory holding the game's executable (`bin\x64`, `Binaries\Win64`,
  `Retail`), not the game root. A directory with no `*.exe` is refused.
- Pass Windows-form paths (`C:\...` or `C:/...`) in single quotes, with no trailing backslash.
  Never hand pwsh a Git Bash `/c/...` path; convert one with `cygpath -m` first.
- Drop `-DataDir` and `-RuntimeDll` when the table above says to omit them.

| Parameter | Used by | Meaning |
|---|---|---|
| `-Build` | apply | `dagherbou` (default) or `wilsjo2`; see `reference/fork-comparison.md` |
| `-Proxy` | apply | Filename the fork's `OptiScaler.dll` is installed as. Default `dxgi.dll`; pick from `assess`'s `freeProxies` |
| `-RestoreComputeSignature` | apply | Also sets `RestoreComputeSignature=true`; `reference/tuning-guide.md` names the titles that need it |
| `-AllowUnknownRuntime` | apply | Accepts an NVIDIA-signed runtime whose hash is not the known one. Only on the user's explicit request |
| `-Finish` | remove | Drops the manifest even when drift remains. Only after the user has seen the drift and asked |
| `-Force` | apply | Lifts only the over-2000-files guard. It does not bypass the anti-cheat refusal |

`provision` and its `-Runtime`, `-RuntimeSource`, `-ScanRoots` parameters belong to
`/gaming:setup`.

## Action router

| Action | When | What it does |
|---|---|---|
| (empty) | No action given | With a game dir: run `status`. "no snapshot" means never applied here, so recommend `assess`; otherwise report the status and recommend. Without a game dir: ask for one. Never runs `apply` or `remove` |
| `assess` | Is this game eligible? | Run `assess`, then the Steam anti-cheat check. Report the verdict. Writes nothing |
| `apply` | Install the mod | `assess` and the Steam check first; stop on `refused` or an uncleared `requiresWebCheck`. Confirm with the user, run `apply`, add the ledger row |
| `remove` | Uninstall the mod | Confirm with the user, run `remove`, report what was kept and any drift, update the ledger row |
| `status` | What changed since apply? | Run `status` and explain its exit code |
| `tune` | Picture or performance | Guide the in-game overlay from `reference/tuning-guide.md`; no script verb |
| `refetch` | Are forks, driver, runtime current? | Run each recheck command in `reference/upstream-watch.md` and update the ledger's Upstream watch rows that changed |

When the request is ambiguous, recommend an action and wait. Never commit to `apply` or `remove`
without the user's confirmation.

## Action: assess

1. Run `-Verb assess '<game-dir>'`. It prints JSON: `verdict` (`refused`, `eligible`, `unknown`),
   `requiresWebCheck`, `refusals`, `dlss` (DLSS DLLs with versions), `dx12`, `proxyCollisions`,
   `freeProxies`, `steamAppId`.
2. `refused`: stop and report the anti-cheat paths. Nothing clears this.
3. `unknown`: report why (no `*.exe`, or no free proxy name) and stop.
4. `eligible` with `requiresWebCheck: true`: run the Steam check below. On-disk absence is not
   absence: server-side and launcher-delivered anti-cheat leave nothing in the install tree.
5. No entry in `dlss` means the game ships no DLSS for the mod to intercept; say so, since the mod
   then does nothing.

Done when the user has one final verdict: refused, unknown, or eligible with the Steam check
cleared or not cleared.

### Steam anti-cheat check

Steam's store page carries a publisher-filed anti-cheat section. Read it with curl and Steam's
age-gate cookies. WebFetch receives the age gate on many titles, and an age gate has no anti-cheat
section, so a WebFetch read of it looks clean when it is not.

```bash
curl -s -b 'birthtime=0; wants_mature_content=1; lastagecheckage=1-0-1900' 'https://store.steampowered.com/app/<steamAppId>/?l=english' | grep -o -i -E 'apphub_AppName">[^<]*|agecheck|anticheat_section' | sort -u
```

| Result | Outcome |
|---|---|
| `anticheat_section` present | Treat as `refused`. Show the user the section's text (the lines after `anticheat_section` on the same page, tags stripped) and stop |
| `apphub_AppName` names the game, no `agecheck`, no `anticheat_section` | Cleared |
| Anything else: fetch failed, `agecheck` present, wrong game, or `steamAppId` is null | Not cleared. Ask the user for the game's Steam store URL and rerun with its app id. With no Steam page, `apply` cannot proceed; say why |

## Action: apply

1. Run the whole `assess` action. Stop on `refused`, `unknown`, or an uncleared check.
2. Pick the proxy from `freeProxies`, `dxgi.dll` first. Cyberpunk 2077 uses `dxgi.dll`, never
   `dbghelp.dll`: its `bin\x64\dbghelp.dll` is a stock game file.
3. Confirm. Show the resolved absolute game directory (`gameDir` from the assess JSON), the build
   and its tag, the proxy name, the `assess` verdict, and the Steam check result, then ask for an
   explicit yes. One confirmation covers one game; never batch several games under one yes.
4. Run `-Verb apply '<game-dir>' -Build <build> -Proxy <proxy>`. The script refuses before any
   write on: an existing manifest (`remove` first), no `*.exe`, over 2000 files, anti-cheat on
   disk, a destination collision, a missing build file (run `/gaming:setup apply`), or a refused
   runtime DLL. Report a refusal as is; never route around it.
5. Add the game's row to `LEDGER.md` in the data directory (see Ledger below).
6. Tell the user how to confirm it runs: launch the game on DX12, enable Neural Rendering in the
   overlay (Insert) after the game has loaded, then look for `DLSS-NR cost` lines in
   `<game-dir>\OptiScaler.log`.

## Action: remove

1. Confirm. Show the resolved absolute game directory and the manifest's build and proxy, then ask
   for an explicit yes. Each game is its own confirmation.
2. Run `-Verb remove '<game-dir>'`. It deletes every manifest file and every known byproduct
   (`reference/reversal-matrix.md`), removes emptied mod directories, and keeps the snapshot.
3. Read the output back to the user:
   - `kept (unknown, not ours)`: files the mod did not install. They stay; the user decides.
   - `MODIFIED` or `REMOVED` entries, with the Steam "Verify integrity" line: pre-install files
     differ from the snapshot and the manifest is kept. After a verify, run `remove` again. After a
     game update the drift is the update, not the mod: show it, and on the user's explicit request
     run `remove -Finish`.
   - `removed: manifest deleted, snapshot kept`: done.
4. Update the game's ledger row: note the removal date.

## Action: status

Run `-Verb status '<game-dir>'`. It lists `ADDED` (tagged `manifest`, `byproduct`, or `unknown`),
`MODIFIED`, `REMOVED`, and any `MANIFEST FILES MISSING` or `MANIFEST FILES CHANGED`.
`INTERRUPTED APPLY` means a crashed `apply` left `pending.json`; `remove` rolls it back.

| Exit | Meaning |
|---|---|
| 0 | No unexpected drift. `ADDED` byproducts, `ADDED` unknown files, and a changed `OptiScaler.ini` (the overlay's Save Settings rewrites it) all exit 0 |
| 1 | A pre-install file was modified or removed, or a manifest file other than `OptiScaler.ini` is missing or changed. Also exit 1 when no snapshot exists (never applied here) |

## Action: tune

The fork's in-game overlay (Insert) is the tuning surface, and its Save Settings rewrites
`OptiScaler.ini`, which `status` already treats as expected. Walk the user through
`reference/tuning-guide.md`: the baseline first, then one change at a time. If the user wants an
ini edit instead, make it with the game closed. `[DlssNr] AutoCapture` stays `false`. Record what
changed in the ledger row's ini deltas and visual verdict columns.

## Action: refetch

Run each recheck command in `reference/upstream-watch.md`, diff against the ledger's Upstream watch table, and Edit only the rows that changed.

## Hard safety rules

- **Never install into a game with anti-cheat on disk or on its Steam page.** There is no bypass.
  Never suggest `-Force` for it, disabling or deleting the anti-cheat, or a different proxy name to
  get past it. A proxy DLL in an anti-cheat game risks the user's account.
- **Never run the forks' `setup_windows.bat`.** It is interactive and hangs a non-interactive shell;
  the script installs the proxy itself, and `provision` never extracts that file.
- **`apply` never overwrites a game file, and `remove` never deletes a file the manifest or the
  byproduct list does not name.** Never delete game files by hand to help either one along.
- **Cyberpunk 2077's proxy is `dxgi.dll`, never `dbghelp.dll`.**
- **`[DlssNr] AutoCapture` stays `false`.** Its default writes raw frame captures into the game
  folder on every launch.
- **The NVIDIA runtime DLL is never committed, bundled, or placed under the plugin root, and this
  skill names no source for it.** It comes only from the three sources `/gaming:setup` documents,
  each hash- or signature-checked.
- **`apply` and `remove` each need the user's explicit confirmation**, one game at a time.

## Ledger

`LEDGER.md` in the data directory holds one row per game; `/gaming:setup apply` seeds it. The script
writes the machine-readable half to `state\<GameKey>\manifest.json`; this skill writes the rows with
Edit. After `apply`, fill: game, exe dir, anti-cheat (the on-disk result and the Steam check),
build and tag, proxy, ini deltas (`Enabled=true AutoCapture=false LogToFile=true LogLevel=2`, plus
`RestoreComputeSignature=true` when passed), driver (the manifest's `driver`), DLL version, applied
date. FPS, visual verdict and crashes stay blank until the user reports them. If `LEDGER.md` is
absent, recommend `/gaming:setup apply` rather than inventing a format.

## Reference index

| Reference | Load when |
|---|---|
| `reference/anticheat-posture.md` | Explaining a refusal, or the user asks why a game is refused |
| `reference/reversal-matrix.md` | Explaining what `remove` deletes, keeps, or reports |
| `reference/fork-comparison.md` | Choosing or switching `-Build` |
| `reference/tuning-guide.md` | The `tune` action, or picking `-RestoreComputeSignature` |
| `reference/upstream-watch.md` | The `refetch` action |

## Volatile specifics

These are true as of the date in each row. `refetch` exists to recheck them.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Known-good runtime: `nvngx_dlssnr.dll` 310.8.0.0, SHA-256 `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E` | `$ModelHash` in the script; NVIDIA-signed copy hashed locally | 2026-09-22 | A DLSS 5 title ships a newer runtime, or `apply` refuses a signed runtime as unknown |
| Default build Dagherbou `v0.2.0-patch1` (prerelease); fallback wilsjo2 `v0.8.3` (newest non-prerelease) | `gh api repos/<owner>/<repo>/releases` | 2026-09-22 | `refetch` shows a new tag, or a pinned asset stops resolving |
| GeForce driver 616.92 WHQL, the driver the mod was verified live on | `nvidia-smi` on the proving-ground machine | 2026-09-22 | A new Game Ready driver |

## Next

- Missing build or runtime DLL: /gaming:setup apply.
- Verdict or setup in doubt: /gaming:setup check.

## Gotchas

- **`status` and `remove` rehash every file under the game dir.** On a large install they take
  minutes, so `status` is not a command to run in a loop. Incremental hashing by size and write time
  is the upgrade path if it bites.
- **`apply` refuses while a manifest exists.** To switch builds or proxies, `remove` first.
- **Each exe directory is its own state.** The state key hashes the full path, so a game with two
  exe directories has two independent installs.
- **Changing the data directory after an apply is a move, not a reconfiguration.** The manifests
  stay at the old path, and `status` and `remove` then see a modded game with no state.
- **The on-disk anti-cheat match is by name.** `reference/anticheat-posture.md` records the tokens,
  the match rule, and its known gap.
