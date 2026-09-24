---
description: "Apply, track, tune, and remove the community DLSS 5 Neural Rendering mod (OptiScaler forks) in a PC game on Windows. Action router: assess (eligibility, launcher, anti-cheat signals), apply (snapshot, then install; anti-cheat risk only with a typed acknowledgement), remove (byte-exact uninstall from the manifest), status (drift and stale-build report against the manifest), reset (back to stock ini plus preset, after confirmation), tune (in-game overlay guidance), capture (save overlay tuning as a local preset), refetch (fork, driver and runtime release watch). Use when: 'apply DLSS 5 to this game', 'is this game safe for the DLSS 5 mod', 'remove the DLSS 5 mod', 'check for new OptiScaler DLSSNR releases', or DLSS 5, DLSSNR, or OptiScaler is mentioned with a game folder."
argument-hint: "[assess|apply|remove|status|reset|tune|capture|refetch] [<game-dir>]"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Route a DLSS 5 mod request to one action. `scripts/Invoke-Dlss5Mod.ps1` does the on-disk work:
eligibility probes, launcher discovery, the anti-cheat sources, snapshot, install, drift report,
byte-exact removal. This skill does what the script cannot: the ban and block research, the user's
confirmation and acknowledgement, the ledger rows, and tuning.

Windows only, PowerShell 7. Run `/gaming:setup` first: `apply` needs a provisioned fork build and
a runtime DLL under the data directory, and this skill never acquires either.

## Resolving paths (do this first)

Resolve each option here, before composing any command, so the command line carries a literal path
or nothing.

| Parameter | Resolution |
|---|---|
| **Data directory** (`-DataDir`) | `${user_config.data_dir}` when set to a non-empty path. If it is empty or still shows an unexpanded `${user_config.data_dir}` token (option unset), omit `-DataDir`: the script defaults to `Gaming\dlss5` under the user's Documents folder and follows a OneDrive-redirected Documents, which a hand-built path does not |
| **Runtime DLL** (`-RuntimeDll`) | `${user_config.runtime_dll}` when set to a non-empty path. If it is empty or still an unexpanded token, omit `-RuntimeDll`: the script defaults to `runtime\nvngx_dlssnr.dll` under the data directory |

Never type an option token onto a command line. An unset option survives substitution as its own
token, and Bash rejects it as a bad substitution before the script starts.

When the ledger path is needed and the data directory option is unset, get the default from the
native side: `pwsh -NoProfile -Command "Join-Path ([Environment]::GetFolderPath('MyDocuments')) Gaming\dlss5"`.
When the data directory is the default, the script refuses every verb but `refetch` and
`selftest` while the legacy `Documents\Gaming\state\` has entries and the new default's `state\` <!-- portability-ok: Windows path, not a shell regex -->
has none. Relay the move it names verbatim; never move the files yourself.

## Running the script

```bash
pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1" -Verb assess '<game-dir>' -DataDir '<data-dir>' -RuntimeDll '<runtime-dll>'
```

- `<game-dir>` is the directory holding the game's executable (`bin\x64`, `Binaries\Win64`, <!-- portability-ok: Windows paths, not a shell regex -->
  `Retail`), not the game root. A directory with no `*.exe` is refused.
- Pass Windows-form paths (`C:\...` or `C:/...`) in single quotes, with no trailing backslash.
  Never hand pwsh a Git Bash `/c/...` path; convert one with `cygpath -m` first.
- Drop `-DataDir` and `-RuntimeDll` when the table above says to omit them.

| Parameter | Used by | Meaning |
|---|---|---|
| `-Build` | apply | `wilsjo2` (default) or `dagherbou` (fallback); see `reference/fork-comparison.md` |
| `-Proxy` | apply | Filename the fork's `OptiScaler.dll` is installed as. Default `dxgi.dll`; pick from `assess`'s `freeProxies` |
| `-Preset` | apply, capture | A per-game preset key: `assess`'s `preset.key` for apply, or the key a new capture is saved under. The base presets apply without it; `reference/presets.md` |
| `-RestoreComputeSignature` | apply | Also sets `[Hotfix] RestoreComputeSignature=true` for a game with no preset; `reference/tuning-guide.md` names the titles that need it |
| `-AllowUnknownRuntime` | apply | Accepts an NVIDIA-signed runtime whose hash is not the known one. Only on the user's explicit request |
| `-Finish` | remove | Drops the manifest even when drift remains. Only after the user has seen the drift and asked |
| `-ConfirmReset` | reset | Writes the reset. Only after the user has seen the printed list of discarded values and said yes |
| `-Force` | apply | Lifts only the over-2000-files guard. Only when the user confirms the directory is the exe directory. It has no effect on the anti-cheat gate |
| `-AcceptAntiCheatRisk` | apply | The game name exactly as the user typed it, after the anti-cheat review below. Never filled in by you |
| `-AntiCheatResearch` | apply | The research summary shown to the user, one paragraph |
| `-AntiCheatSources` | apply | The research's `https://` URLs, comma-separated |
| `-AntiCheatReviewId` | apply | `antiCheat.reviewId` from the `assess` the user reviewed. `apply` refuses when its own reread gives another id |

A game name with an apostrophe breaks a single-quoted Bash argument: write `'Tom Clancy'\''s
Rainbow Six'`. `-AntiCheatResearch` text takes the same escape.

`provision` and its `-Runtime`, `-RuntimeSource`, `-ScanRoots` parameters belong to
`/gaming:setup`.

## Action router

| Action | When | What it does |
|---|---|---|
| (empty) | No action given | With a game dir: run `status`. "no snapshot" means never applied here, so recommend `assess`; otherwise report the status and recommend. Without a game dir: ask for one. Never runs `apply` or `remove` |
| `assess` | Is this game eligible? | Run `assess`. Report the launcher, the verdict and the anti-cheat status. Writes nothing |
| `apply` | Install the mod | `assess` first; stop on verdict `refused`, `not-a-candidate` or `unknown`. Any anti-cheat status but `none-disclosed` runs the anti-cheat review. Confirm with the user, run `apply`, add the ledger row |
| `remove` | Uninstall the mod | Confirm with the user, run `remove`, report what was kept and any drift, update the ledger row |
| `status` | What changed since apply? | Run `status` and explain its exit code and its installed-build line |
| `reset` | Undo overlay changes | Show what it discards, ask, then rewrite `OptiScaler.ini` to the stock ini plus the recorded preset |
| `tune` | Picture or performance | Start from the game's preset, then guide the in-game overlay from `reference/tuning-guide.md`; no script verb |
| `capture` | Keep the overlay tuning | Run `capture` after the user's Save Settings; it writes the game's local preset. Writes nothing in the game folder |
| `refetch` | Are forks, driver, runtime current? | Run `refetch`, read the page-backed items, update only the ledger's Upstream watch rows that changed |

When the request is ambiguous, recommend an action and wait. Never commit to `apply` or `remove`
without the user's confirmation.

## Action: assess

1. Run `-Verb assess '<game-dir>'`. It prints JSON:
   - `launcher` (Steam, Epic Games Launcher, EA app, Origin, Battle.net, GOG Galaxy, Ubisoft
     Connect, Xbox app, or `unknown`), `launcherSource`, `gameName`, and `discoveryGaps` (what
     launcher discovery could not read);
   - `verdict` (`refused`, `not-a-candidate`, `eligible`, `unknown`) and `refusals`;
   - `antiCheat`: `status` (`signals`, `unknown`, `none-disclosed`), `signals`, `unchecked`,
     `note`, `awacy` (the AreWeAntiCheatYet commit read and its matching entries) and `steam` (the
     store page read); plus `acknowledgementRequired`;
   - `upscalers` (each upscaler DLL found, with `family` DLSS, FSR or XeSS, and its version; the
     mod's own copies do not count), `dx12`, `proxyCollisions`, `freeProxies`, `steamAppId`;
   - `preset`: the effective preset, with each ini key's `source` (`shipped-base`, `shipped`,
     `local-base` or `local`). `preset.key` is the matching per-game preset, or null when only the
     bases apply. `presetError` names a preset file that failed validation; report it. A broken
     base makes every `apply` refuse, and a broken per-game file cannot be passed as `-Preset`,
     until the file is fixed;
   - `installedBuild`: null when the mod is not applied here, else the manifest's build against
     its current pin, as in `status`.
2. `refused`: the directory is under `WindowsApps`. Stop and say why
   (`reference/launchers.md`). Nothing clears this.
3. `not-a-candidate`: the game ships no DLSS, FSR 2+ or XeSS, so the mod has nothing to hook. Tell
   the user plainly: "This game has no upscaler for the mod to hook, so it will not help." A 2D or
   pixel-art game such as Stardew Valley is the typical case. Stop, before any anti-cheat review.
   The only way forward is the user's: a wiki-listed upscaler mod, then `assess` again
   (`reference/candidate-selection.md`). There is no flag that skips this verdict.
4. `unknown`: report why (no `*.exe`, or no free proxy name) and stop.
5. `eligible`: report the launcher, the game name and the anti-cheat status with every signal and
   every `unchecked` line. `none-disclosed` carries its `note`: say it means no kernel anti-cheat
   was disclosed, not that the game has none. For an online or co-op game, tell the user to play
   modded only solo or offline.
6. Done when the user has the launcher, one verdict, and the anti-cheat status with its signals
   and unchecked sources.

### Anti-cheat review (before an acknowledgement)

Run this when `apply` is requested and `acknowledgementRequired` is true. The default is still to
refuse; this review is how the user makes an informed call. Never disable, bypass, delete or tamper
with an anti-cheat, and never suggest doing so, a different proxy name, or `-Force` as a way past
it.

1. **Show what was found.** Every `signals` line and every `unchecked` line, verbatim. With
   launcher `unknown`, also show `discoveryGaps` and ask where the game came from: a Battle.net
   game with no Uninstall entry reads as `unknown`, and its EULA applies all the same. For a
   Battle.net title, show Blizzard EULA 1.C.i and 1.C.ii in full from
   `reference/anticheat-posture.md`. Link the title's PCGamingWiki page for the user to read.
2. **Research reported bans and blocks** for this title and each named anti-cheat, live:
   - the fork issue trackers: `gh search issues '<title>' --repo Dagherbou/OptiScaler_DLSSNR`,
     the same for `wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass` and `optiscaler/OptiScaler`, each
     also with the anti-cheat's name;
   - the OptiScaler wiki: the title's page and its row in the compatibility list;
   - a targeted web search: `"<title>" OptiScaler ban`, `"<title>" <anti-cheat> dll ban`, and
     `"<title>" dxgi.dll anti-cheat`.

   Summarize in one paragraph: whether users report a block (the game will not start with the DLL)
   or a ban (the account was flagged), how recent, and on which build. Keep block and ban apart
   (`reference/anticheat-posture.md`). Say plainly when nothing was found; that is not safety. List
   every source URL.
3. **Ask.** Say that installing is at the user's own risk and can cost the account, and ask them
   to type the game's name, as `gameName` shows it, to go ahead. Anything else is a no. Never type
   it for them or infer it from an earlier message.
4. Pass what they typed as `-AcceptAntiCheatRisk`, the summary as `-AntiCheatResearch`, the URLs
   as `-AntiCheatSources`, and the reviewed `antiCheat.reviewId` as `-AntiCheatReviewId`. The
   script refuses a name that does not match `gameName`, an acknowledgement without research or
   `https://` sources, and a review id that no longer matches: a signal that appeared after the
   review was never shown to the user. On that refusal, run `assess` and this review again.

## Action: apply

1. Run the whole `assess` action. Stop on verdict `refused`, `not-a-candidate` or `unknown` (an
   anti-cheat status of `unknown` is not a stop; it runs the review). When
   `acknowledgementRequired` is true, run the anti-cheat review above; stop unless the user typed
   the name.
2. Pick the proxy: the preset's `proxy` when `freeProxies` lists it, else `freeProxies` with
   `dxgi.dll` first; for an Xbox app game, `winmm.dll` first (`reference/launchers.md`). Cyberpunk
   2077 uses `dxgi.dll`, never `dbghelp.dll`: its `bin\x64\dbghelp.dll` is a stock game file.
3. `preset.key` null in the assess JSON (no per-game preset): offer the research step below before
   applying with the bases alone. The user may decline; that is a valid apply.
4. Confirm. Show the resolved absolute game directory (`gameDir` from the assess JSON), the
   launcher, the build and its tag (`wilsjo2` unless the user chose the `dagherbou` fallback), the
   proxy name, the `assess` verdict, the anti-cheat status
   (and, when acknowledged, the typed name), and the preset: its key (or "bases only"), and each
   ini key as `[Section] Key=Value` with its source and its `why`. Then ask for an explicit yes.
   The typed game name is the risk acknowledgement, not this confirmation; ask for both. One
   confirmation covers one game; never batch several games under one yes.
5. Run `-Verb apply '<game-dir>' -Build <build> -Proxy <proxy>`, plus `-Preset <key>` when
   `preset.key` is not null, plus the four acknowledgement parameters when the review ran. The
   script rereads every anti-cheat source and refuses before any write on: an existing manifest
   (`remove` first), no `*.exe`, a `WindowsApps` path, over 2000 files, no upscaler DLL (not a
   candidate), a preset key off the allow-list or allow-listed only for another build,
   `AutoCapture` in a preset, a value of the wrong type, one hotkey bound to two actions, a
   destination
   collision, a missing build file (run `/gaming:setup apply`), a refused runtime DLL, an
   anti-cheat status other than `none-disclosed` without a matching acknowledgement, or a folder
   its write probe cannot write. Report a refusal as is; never route around it.
6. Print the setup guide: the preset's `manual` lines from the apply output, numbered, under the
   game's title. These are the settings the script cannot write. With no preset, point to the
   baseline in `reference/tuning-guide.md`.
7. Add the game's row to `LEDGER.md` in the data directory (see Ledger below).
8. Tell the user how to confirm it runs: launch the game on DX12, enable Neural Rendering in the
   overlay after the game has loaded, then look for `DLSS-NR cost` lines in
   `<game-dir>\OptiScaler.log`. The overlay key is Insert unless the preset sets
   `[Menu] ShortcutKey`; then name that key, here and wherever a preset's `manual` line says
   Insert. Name the Neural Rendering toggle key too when `[DlssNr] ToggleKey` is set.

### Research a preset (no preset matched)

1. Start from the `assess` JSON: `upscalers`, `dx12`, `steamAppId`, and the engine the path
   suggests.
2. Read only the trusted sources in the "Per-game config sources" table of
   `reference/candidate-selection.md`: the OptiScaler wiki's per-game page, the forks' README and
   `INSTALL-DLSSNR.md` game notes, and the fork issue trackers (one user's values each). Never use
   a source that table marks untrusted, such as FlashAust-authored guide issues or SEO mod sites.
   Never apply an NGX registry edit.
3. Sort each finding. An ini key on the allow-list in `reference/presets.md` with a trusted source
   goes in `ini`, with its condition in `why`. An in-game setting goes in `manual`. A claim with
   conflicting reports stays out, or goes in `manual` as "try either" with both sources.
4. Write `presets\<key>.json` in the data directory in the format of `reference/presets.md`, with <!-- portability-ok: Windows path, not a shell regex -->
   a `match` on the `steamAppId` when `assess` reported one, else on the game's `*.exe` name in
   the exe directory (`match.exe`), each source's URL and today's date, and a `recheck`. Rerun
   `assess` and confirm it reports the preset with no `presetError`.
5. Note in the ledger row that the preset is local and was researched today.
6. When the preset would help other users, suggest an issue on this plugin's repository carrying
   the file and its sources, so it can ship after review (`reference/presets.md`, Community
   presets).

## Action: remove

1. Confirm. Show the resolved absolute game directory and the manifest's build and proxy, then ask
   for an explicit yes. Each game is its own confirmation. Read the build and proxy from
   `manifest.json` in the data directory's `state` folder, in the subfolder named by the `gameKey`
   that `assess` prints for this game directory; never guess them.
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

The last line compares the manifest's `build`, `tag` and `buildSha256` with that build's current
pin. `installed build is older than the current pin` means this game predates a pin update: offer
the roll-out steps in `reference/upstream-watch.md`, Updating a pin. `unknown, re-apply to record`
means the manifest predates recorded build tags. Neither changes the exit code.

| Exit | Meaning |
|---|---|
| 0 | No unexpected drift. `ADDED` byproducts, `ADDED` unknown files, and a changed `OptiScaler.ini` (the overlay's Save Settings rewrites it) all exit 0 |
| 1 | A pre-install file was modified or removed, or a manifest file other than `OptiScaler.ini` is missing or changed. Also exit 1 when no snapshot exists (never applied here) |

## Action: reset

Undoes the overlay's Save Settings without a remove and apply: the game's `OptiScaler.ini` goes
back to the build's stock ini plus the preset recorded in the manifest (`reference/presets.md`,
Reset). Offer `capture` first when the user may want to keep the current tuning.

1. Run `-Verb reset '<game-dir>'` without `-ConfirmReset`. It prints each value it would discard
   and writes nothing. Stop and relay a refusal as is.
2. Show the user that list, the resolved game directory, and the manifest's build and tag, and ask
   for an explicit yes. Ask with the game closed.
3. On yes, rerun with `-ConfirmReset`. Report the rewrite; the manifest now records the file's
   hash, so `status` stays clean and `remove` stays byte-exact.
4. Note the reset in the game's ledger row.

## Action: tune

The fork's in-game overlay (Insert) is the tuning surface, and its Save Settings rewrites
`OptiScaler.ini`, which `status` already treats as expected. Start from the game's preset: read
`preset` from `manifest.json` in the game's state folder (or from `assess` before an apply), and
print its `manual` lines as the setup guide. Then walk the user through
`reference/tuning-guide.md`: the baseline first, then one change at a time. When the user is happy
and has pressed Save Settings, offer `capture` to keep the result. A hotkey or picture default the
user wants in every game belongs in the local base, `presets\_base.json` in the data directory; <!-- portability-ok: Windows path, not a shell regex -->
offer to write it there (hotkeys: `reference/presets.md`). If the user wants an ini edit instead,
make it with the game closed. `[DlssNr] AutoCapture` stays `false`. Record what changed in the
ledger row's ini deltas and visual verdict columns.

## Action: capture

1. Tell the user to press Save Settings in the overlay first; `capture` reads what it wrote.
2. Run `-Verb capture '<game-dir>'`. The game's preset key comes from its manifest or its
   `match`. With neither, `capture` refuses and asks for `-Preset <key>`: propose a key from the
   game name (lowercase letters, digits, hyphens) and rerun with it.
3. Report the captured keys and the file. Report every `not captured` line: keys off the
   allow-list stay in the game's ini only, and an `AutoCapture=true` line means the user turned
   frame capture on; tell them to set it back to `false`. A `conflict` line is a captured hotkey
   whose key another layer already binds: the other keys were still saved. Show both bindings and
   the one the preset keeps, and ask which action the user wants on that key; after they rebind
   one (in the overlay, or in the named preset layer), run `capture` again.
4. The next `apply` of this game writes the captured values. `capture` never writes into the game
   folder, so `remove` stays byte-exact.
5. Note the capture in the ledger row. Suggest upstreaming the preset as a community preset,
   with the game, build, driver and what the user saw (`reference/presets.md`, Community presets).
   A captured `why` is not a source, so the issue must carry the evidence.
6. Done when the user has the captured keys, the preset file path, and every not-captured line.

## Action: refetch

1. Run `-Verb refetch`. It checks both forks' releases, upstream OptiScaler's latest release, the
   local driver, and the runtime DLL's version, then prints JSON and merges it into
   `cache\upstream.json` in the data directory. An item with `error` set was not checked this run:
   its `found` is the previous value, so report it as unchecked, never as unchanged. `gh` is the
   only tool it needs that setup does not.
2. Read the page-backed items `refetch` cannot: NVIDIA's GeForce news for new native DLSS 5 titles
   and drivers, and whether upstream OptiScaler merged the Neural Rendering pull requests (the
   commands are in `reference/upstream-watch.md`). For each game row in the ledger, rerun `assess`
   on its exe dir, because a publisher can add anti-cheat after an apply, and compare the
   anti-cheat status and signals with the row. Check the row's preset `recheck` trigger against
   what changed.
3. Diff everything against the ledger's Upstream watch table. Edit only the rows that changed and
   their Checked dates. A run where nothing changed is reported as a no-change run.
4. For each change, say what it means using the "What a change means" table in
   `reference/upstream-watch.md`. A new pin is a plugin release, never an edit to the installed
   script. A game with an anti-cheat signal its ledger row does not record: show it and
   recommend `remove`. A preset whose
   `recheck` trigger fired: re-read its sources, then update the local preset, or suggest an issue
   for a shipped one.
5. Done when every changed row carries today's Checked date and each change has its meaning
   stated, or the run is reported as a no-change run.

## Hard safety rules

- **Anti-cheat: refuse by default; install only on the user's typed acknowledgement.** Any
  anti-cheat signal, or an `unknown` status, refuses `apply` unless the user typed the game's name
  after the anti-cheat review: every signal and unchecked source shown, live ban and block research
  summarized with sources. A proxy DLL in an anti-cheat game can get the game blocked or the
  account banned, and the user carries that risk. Never pass `-AcceptAntiCheatRisk` with a name the
  user did not type in this conversation for this game.
- **Never disable, bypass, delete or tamper with any anti-cheat, and never suggest it.** Nor
  `-Force` or a different proxy name as a way past the gate. The mod goes in beside the anti-cheat,
  unchanged.
- **`not-a-candidate` and a `WindowsApps` path have no override.**
- **Never run the forks' `setup_windows.bat`.** It is interactive and hangs a non-interactive shell;
  the script installs the proxy itself, and `provision` never extracts that file.
- **`apply` never overwrites a game file, `remove` never deletes a file the manifest or the
  byproduct list does not name, and `reset` writes only the manifest-owned `OptiScaler.ini`.**
  Never delete game files by hand to help any of them along.
- **Cyberpunk 2077's proxy is `dxgi.dll`, never `dbghelp.dll`.**
- **`[DlssNr] AutoCapture` stays `false`.** Its default writes raw frame captures into the game
  folder on every launch. No preset can set it, `capture` never captures it, and a preset sets
  only the allow-listed keys in `reference/presets.md`. Never widen that list to fit a preset.
- **The NVIDIA runtime DLL is never committed, bundled, or placed under the plugin root, and this
  skill names no source for it.** It comes only from the three sources `/gaming:setup` documents,
  each hash- or signature-checked.
- **`apply`, `remove` and `reset -ConfirmReset` each need the user's explicit confirmation**, one
  game at a time.

## Ledger

`LEDGER.md` in the data directory holds one row per game; `/gaming:setup apply` seeds it. The script
writes the machine-readable half to `state\<GameKey>\manifest.json`; this skill writes the rows with <!-- portability-ok: Windows path, not a shell regex -->
Edit. After `apply`, fill: game, exe dir, anti-cheat (the status and every signal; when
acknowledged, `acknowledged <date> as '<typed name>'`, the research summary in one line, and its
source URLs), build and tag (the manifest's `build` and `tag`), proxy, ini deltas (`Enabled=true AutoCapture=false LogToFile=true LogLevel=2`, plus
`RestoreComputeSignature=true` when passed, plus each preset key), driver (the manifest's
`driver`), DLL version, applied date. Notes gets `launcher <launcher>`. With preset keys, Notes also gets `preset <key>` (or `bases only`) with each key's
source (`shipped-base`, `shipped`, `local-base` or `local`) and the newest `asOf` among its sources. FPS, visual verdict and crashes stay blank until the user reports them. If `LEDGER.md` is
absent, recommend `/gaming:setup apply` rather than inventing a format.

## Reference index

| Reference | Load when |
|---|---|
| `reference/anticheat-posture.md` | The anti-cheat review, explaining a status or a refusal, or quoting the Blizzard EULA |
| `reference/launchers.md` | Which launcher a game came from, what `discover` reads, or an Xbox app game |
| `reference/candidate-selection.md` | Explaining `not-a-candidate`, which games the mod can help, engine notes, or which per-game config sources to trust |
| `reference/reversal-matrix.md` | Explaining what `remove` deletes, keeps, or reports |
| `reference/fork-comparison.md` | Choosing or switching `-Build` |
| `reference/presets.md` | Preset format, the four layers and their precedence, the per-build ini allow-list, hotkeys, `capture`, `reset`, writing a local preset, or contributing one |
| `reference/tuning-guide.md` | The `tune` action, or picking `-RestoreComputeSignature` |
| `reference/upstream-watch.md` | The `refetch` action, a new pin, or a game whose installed build is older than the current pin |

## Volatile specifics

These are true as of the date in each row. `refetch` exists to recheck them.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Known-good runtime: `nvngx_dlssnr.dll` 310.8.0.0, SHA-256 `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E` | `$ModelHash` in the script; NVIDIA-signed copy hashed locally | 2026-09-22 | A DLSS 5 title ships a newer runtime, or `apply` refuses a signed runtime as unknown |
| Default build wilsjo2 `v0.8.3` (newest non-prerelease); fallback Dagherbou `v0.2.0-patch1` (prerelease). Default chosen from the owner's live A/B, issue #4429 | `gh api repos/<owner>/<repo>/releases`; `reference/fork-comparison.md` | 2026-09-24 | `refetch` shows a new tag, or a pinned asset stops resolving |
| GeForce driver 616.92 WHQL, the driver the mod was verified live on | `nvidia-smi` on the proving-ground machine | 2026-09-22 | A new Game Ready driver |
| Steam requires the store-page anti-cheat field only for client-side kernel-mode anti-cheat; for anything else it is optional | Steamworks announcement 4547038620960934857, read through the Steam event API | 2026-09-23 | Valve changes the anti-cheat disclosure rule |
| AreWeAntiCheatYet `games.json` fields `name`, `anticheats`, `status` (Linux and Proton support), `storeIds` (`steam`, `epic`); 1167 entries at commit `e31a7e6` | `https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/<sha>/games.json`, parsed live; `components/Legend.tsx` for the status meaning | 2026-09-23 | `assess` reports an AreWeAntiCheatYet fetch failure that persists, or the file's fields change |
| Blizzard EULA revised March 21, 2024; section 1.C.i and 1.C.ii text as quoted in `reference/anticheat-posture.md` | The EULA page, fetched | 2026-09-23 | The page shows a newer revision date |

## Next

- Missing build or runtime DLL: /gaming:setup apply.
- Verdict or setup in doubt: /gaming:setup check.

## Gotchas

- **`apply`, `status` and `remove` hash every file under the game dir.** `apply` snapshots the
  whole tree, and `status` and `remove` rehash it. On a large install each takes minutes, so
  `status` is not a command to run in a loop. Incremental hashing by size and write time
  is the upgrade path if it bites.
- **`apply` refuses while a manifest exists.** To switch builds or proxies, `remove` first.
- **Each exe directory is its own state.** The state key hashes the full path, so a game with two
  exe directories has two independent installs.
- **Changing the data directory after an apply is a move, not a reconfiguration.** The manifests
  stay at the old path, and `status` and `remove` then see a modded game with no state.
- **The upscaler match is by DLL name.** An upscaler compiled into the game's executable leaves
  no DLL, so that game reads as `not-a-candidate`; `reference/candidate-selection.md` lists the
  names and this gap.
- **The on-disk anti-cheat match is by name.** `reference/anticheat-posture.md` records the tokens,
  the match rule, and its known gap.
- **`assess` and `apply` read the network.** Each fetches AreWeAntiCheatYet (its commit SHA through
  the unauthenticated, rate-limited GitHub API) and, for Steam, the store page. Offline, the
  status is `unknown`, never `none-disclosed`.
- **The EA app's own install list is not read.** `discover` finds EA games only under
  `%ProgramFiles%\EA Games`; a game in another EA library folder is still named `EA app` when
  `assess` is pointed at it, by its `__Installer` marker.
