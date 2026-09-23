---
description: "Verify and provision the gaming plugin's DLSS 5 mod prerequisites on Windows. check (read-only): pwsh, NVIDIA GPU and driver, data directory, runtime DLL, provisioned fork builds, orphaned state. apply: create the data directory, seed the ledger, place the runtime DLL from a configured path, an installed DLSS 5 title, or the configured runtime source, and download the pinned fork builds. Use when: 'set up the gaming plugin', 'set up DLSS 5', 'is my DLSS 5 setup ready', 'provision the DLSS 5 mod'. Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and provision the prerequisites for `/gaming:dlss5`, per the uniform setup contract
(`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the marketplace repository).
No argument or `check` runs the read-only check; `apply` runs `check`, provisions through the
script's own verbs, then runs `check` again. Windows only.

All provisioning goes through `${CLAUDE_PLUGIN_ROOT}/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1`
(below: the script). Its `provision` verbs own download, hash verification, extraction and the
runtime gate, and its selftest covers them; this body calls them and never restates their logic.

## Resolving paths (do this first)

Resolve each option to a literal value before composing any command. A command line carries the
resolved path, never a `${user_config.*}` token: an unset option leaves the token in place, and
Bash then fails with `bad substitution` before pwsh starts.

| Option | Resolution | Passed as |
|---|---|---|
| **`<data-dir>`** | `${user_config.data_dir}` when non-empty and not still showing the unexpanded token; otherwise the output of the default command below. Changing it after an apply is a MOVE of the directory, not a reconfiguration: every manifest stays at the old root | `-DataDir '<data-dir>'` on every call |
| **`<runtime-dll>`** | `${user_config.runtime_dll}` when set; otherwise `<data-dir>\runtime\nvngx_dlssnr.dll` | `-RuntimeDll` ONLY when the option is set. Passing the default path marks it configured, and `provision -Runtime` then refuses a failing file without scanning |
| **`<runtime-source>`** | `${user_config.runtime_source}` when set; otherwise none | `-RuntimeSource` ONLY when set. A path or a plain `https://` URL. The value is stored in plain text in `settings.json`, so a URL with a query string (where signed-URL credentials live) is refused. A private store is synced to a path by the user's own tooling |

The default `data_dir` follows OneDrive Known Folder Move, which `$env:USERPROFILE\Documents`
does not:

```bash
pwsh -NoProfile -Command "Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Gaming\dlss5'"
```

Pass Windows-form paths in single quotes (`'D:\Gaming'`), never a Git Bash `/d/...` path. Run the
multi-line probes in steps 5 and 7 through the PowerShell tool: they contain single quotes, so a
single-quoted Bash argument cannot carry them, and a double-quoted one lets Bash expand `$` before
pwsh starts. A one-line probe with no single quote in it (step 1) runs from Bash in single quotes.

## `check` (read-only)

Report a PASS/FAIL/INFO table with one remediation line per FAIL. Write nothing, copy nothing,
download nothing, and never call `provision` in any form.

1. **pwsh 7.** `pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'`. FAIL when absent
   or below 7: the script declares `#Requires -Version 7`.
2. **NVIDIA GPU and driver.** `nvidia-smi --query-gpu=name,driver_version --format=csv,noheader`.
   FAIL when `nvidia-smi` is absent or lists no GPU. Report the name and driver. A GPU outside the
   RTX 50 series is FAIL (see the verification record below).
3. **Data directory.** Absent is INFO (`apply` creates it). Present is PASS. `check` does not test
   writability, because that takes a write; the directory creation in `apply` is the test.
4. **Ledger.** `<data-dir>\LEDGER.md` present is PASS; absent is INFO (`apply` seeds it).
5. **Runtime DLL.** Hash `<runtime-dll>`:

   ```powershell
   $dll = '<runtime-dll>'
   if (Test-Path -LiteralPath $dll) {
     (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
     $s = Get-AuthenticodeSignature -LiteralPath $dll; "$($s.Status) $($s.SignerCertificate.Subject)"
     $v = (Get-Item -LiteralPath $dll).VersionInfo; '{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart
   }
   ```

   PASS when the hash is the known-good value. An NVIDIA-signed file (status `Valid`, signer
   subject containing `CN=NVIDIA Corporation`) at 310.8.0.0 or later with a
   different hash is FAIL: the gate refuses it unless `-AllowUnknownRuntime` is passed, which is
   the user's explicit call and never a default. A missing or refused file is FAIL. When
   `runtime_dll` is set, the remediation is to fix or unset it: `provision -Runtime` refuses a
   configured file without looking further. When it is unset, report what `apply` would do:
   run the scan in step 7 and name each candidate with its gate result, and say whether
   `<runtime-source>` is set. The remediation then names the three remedies in the order
   `provision -Runtime` tries them: set `runtime_dll` to a copy you already have; install a DLSS 5
   title on this machine; set `runtime_source` to a copy you control. The plugin names no source
   of its own for this file.
6. **Runtime source.** INFO: set or not. A URL with a query string, or a URL scheme other than
   `https://`, is FAIL: the script refuses it.
7. **Steam library scan.** Read-only; it lists candidates and copies nothing:

   ```powershell
   $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath # portability-ok: Windows registry path, PowerShell only
   if ($steam) {
     $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
     $libs = @($steam) + @(if (Test-Path -LiteralPath $vdf) { [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' } }) # portability-ok: .NET regex in PowerShell, not grep or sed
     $libs | ForEach-Object { Join-Path ($_ -replace '/', '\') 'steamapps\common' } | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique |
       ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter nvngx_dlssnr.dll -File -Force -ErrorAction SilentlyContinue } |
       ForEach-Object { $v = $_.VersionInfo; $sig = Get-AuthenticodeSignature -LiteralPath $_.FullName; [pscustomobject]@{ Path = $_.FullName; Sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash; Version = '{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart; Signature = $sig.Status; Signer = $sig.SignerCertificate.Subject } } | Format-List
   }
   ```

   A candidate passes the gate on the known-good hash, or on a `Valid` signature whose signer
   subject contains `CN=NVIDIA Corporation`, at 310.8.0.0 or later, plus `-AllowUnknownRuntime`. A candidate beside an `OptiScaler.ini` is a copy the mod
   placed in a game, not a native title; step 9 uses it.
8. **Fork builds.** For `dagherbou` and `wilsjo2`, read `<data-dir>\builds\<build>\.provisioned.json`: <!-- portability-ok: Windows path, not a shell regex -->
   - no marker, directory absent or empty: INFO, never provisioned (`apply` provisions it);
   - marker present and every allow-list entry present (dagherbou: `OptiScaler.dll`,
     `OptiScaler.ini`, `OptiScaler\`, `Licenses\`, `nvngx.dll_dlssnr.dll`; wilsjo2: the first
     four), marker `sha256` equal to the pin below: PASS;
   - marker present, an allow-list entry missing: FAIL, provisioned then emptied. `provision` treats
     a matching marker as done, so the remediation is to delete `<data-dir>\builds\<build>\`, then <!-- portability-ok: Windows path, not a shell regex -->
     run `apply`;
   - marker `sha256` differing from the pin: FAIL, provisioned from an unexpected asset. `apply`
     re-provisions it.
9. **Orphaned state.** Read `gameDir` from each `<data-dir>\state\*\snapshot.json`, <!-- portability-ok: Windows path, not a shell regex -->
   `manifest.json` and `pending.json`. A `pending.json` is FAIL (an interrupted apply; run
   `/gaming:dlss5 remove <gameDir>`). A `manifest.json` whose `gameDir` no longer exists is FAIL
   (the game moved or was uninstalled; move it back and run `remove`, or delete that state
   directory if it is gone for good). A snapshot-only directory whose `gameDir` is gone is INFO.
   Two probes for a `data_dir` changed after an apply, since nothing on disk records the previous
   root: a step 7 candidate beside an `OptiScaler.ini` whose directory no manifest under
   `<data-dir>` names as `gameDir` is FAIL (a modded game this data directory does not track); and
   another directory still holding `state\` is FAIL: the default (`Gaming\dlss5` under Documents)
   when `<data-dir>` is not the default, or the legacy default (`Gaming` under Documents) when
   `<data-dir>\state\` is absent. The remediation for both is to MOVE the old directory's contents
   (`runtime\`, `state\`, `builds\`, `cache\` and `LEDGER.md`) to `<data-dir>`; without its
   manifest, `remove` cannot undo the mod. With `data_dir` unset, the script refuses every verb
   but `refetch` and `selftest` on the legacy case.
10. **`gh`.** INFO only: `gh --version`. `refetch` needs it; setup and apply do not, because
    `provision` downloads by direct release URL.

## `apply` (idempotent)

Run `check`, then these steps in order; stop before step 1 when step 9 reports another
directory holding `state\`, since step 1 would start an empty state tree beside it. `<script>` is
`${CLAUDE_PLUGIN_ROOT}/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1`.

1. Create the tree:
   `pwsh -NoProfile -Command "New-Item -ItemType Directory -Force -Path '<data-dir>\state','<data-dir>\runtime','<data-dir>\builds','<data-dir>\cache' | Out-Null"`. <!-- portability-ok: Windows paths inside a pwsh argument, not a shell regex -->
2. Seed the ledger only when `<data-dir>\LEDGER.md` is absent: copy `reference/ledger-template.md`
   there, replacing `<data-dir>` with the resolved path. Never overwrite an existing ledger.
3. Place the runtime DLL, adding `-RuntimeDll` and `-RuntimeSource` only per the resolution table:
   `pwsh -NoProfile -File "<script>" -Verb provision -Runtime -DataDir '<data-dir>'`.
   When the user has explicitly asked to accept an NVIDIA-signed runtime that fails the hash, add
   `-AllowUnknownRuntime` and say so in the report; never add it otherwise. On a non-zero exit,
   relay the printed remedies and refusals verbatim and continue to step 4.
4. Provision both pinned fork builds, so an apply that falls back to `wilsjo2` finds its files:
   `pwsh -NoProfile -File "<script>" -Verb provision -Build dagherbou -DataDir '<data-dir>'`, then
   the same with `-Build wilsjo2`.
5. Run `check` again and report its actual table; never report success from an exit code alone.

Re-running `apply` changes nothing: the directories exist, the ledger is kept, `provision -Runtime`
prints `runtime ok` and copies nothing, and `provision` prints `already provisioned` for a build
whose marker matches its pin.

Two hard rules. `apply` never runs `setup_windows.bat`, and neither may you by hand: it is
interactive, and `provision` never extracts it. And `apply` never fetches the runtime DLL from
anywhere but the three sources `provision -Runtime` tries.

## Verification record

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Known-good runtime: `nvngx_dlssnr.dll` 310.8.0.0, SHA-256 `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E` | `$ModelHash` in the script, hashed from a working install | 2026-09-22 | `/gaming:dlss5 refetch` reports a different runtime version, or an NVIDIA-signed runtime fails the hash |
| Primary fork pin: `Dagherbou/OptiScaler_DLSSNR` tag `v0.2.0-patch1` (a prerelease), asset `OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip`, SHA-256 `5DB547216FA8A7DBD8AB0A193DA1E3BCE0EA4BD71F91189AFA4ED2EDE8BB9561` | `gh api repos/Dagherbou/OptiScaler_DLSSNR/releases`; the release publishes no checksum, so the hash is a local-copy attestation | 2026-09-21 | a new release on that repo, or `refetch` reports a tag change |
| Fallback fork pin: `wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass` tag `v0.8.3`, asset `OptiScaler-NR-v0.8.3.zip`, SHA-256 `3F2D26FB136D964A394BF50896D082156173153A2A55B88E1995277B4DABE3C8` | `gh api repos/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases`; the hash matches the release's own `.sha256` sidecar | 2026-09-21 | a new non-prerelease on that repo, or `refetch` reports a tag change |
| DLSS 5 officially supports RTX 50-series GPUs only | https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/ | 2026-09-20 | NVIDIA ships DLSS 5 support for another GPU series |

## Next

/gaming:dlss5 assess <game-dir>

## Gotchas

- **`VersionInfo.FileVersion` misreads the runtime DLL.** NVIDIA's `nvngx_dlssnr.dll` reports
  `310,8,0,0` there. Read the numeric `FileMajorPart` to `FilePrivatePart` fields, as steps 5 and 7
  do; `refetch` reports the same numeric form.
- **A probe containing single quotes cannot run from Bash in single quotes.** Run it through the
  PowerShell tool instead of switching to double quotes, which let Bash expand every `$`.

## What this skill does NOT do

- Apply, remove or tune the mod in a game. That is `/gaming:dlss5`.
- Write Claude Code user settings or `pluginConfigs`. Reconfigure with
  `/plugin configure gaming@<marketplace>`, then rerun `check` in a fresh session.
- Delete anything. Emptied builds and orphaned state are reported with a remediation the user runs.
- Name, bundle or download a source for the runtime DLL beyond the three the user controls.
