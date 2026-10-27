# Elevation matrix for Windows

Which Windows capabilities the skill can and cannot exercise when the process is not Administrator, and why.

## Policy

- **Admin is never assumed.** Orchestrator detects elevation via `Test-IsElevated.ps1` (Win32 SID lookup) and runs unconditionally, with no UAC prompt.
- **Non-elevated runs emit UNKNOWN** for gated signals with `needs_admin: true` in the check result, plus `detail.admin_fields` listing fields that would have been populated.
- **Loud upfront communication, no interactive prompts.** Pre-run banner enumerates admin-only capabilities and points to the elevated pass below. The run itself never asks; the user either asks the session for the pass or lets the skill continue with reduced coverage.
- **Suppress via `-SkipBanner`** for scripted/scheduled invocations.

## Capabilities that require elevation

See `Get-ElevationMatrix` (`scripts/windows/lib/Get-ElevationMatrix.ps1`) for the admin-gated capabilities, and `Get-NonElevatedCoverage` (`scripts/windows/lib/Get-NonElevatedCoverage.ps1`) for the banner's "Covered non-elevated" list.

## How to run elevated

The audit session drives an optional elevated pass; when it may be offered, what the owner is shown and what counts as the owner's yes are in [SKILL.md, "Elevated pass"](../../SKILL.md#elevated-pass). This section states the mechanism. The owner's own account must hold the admin token: an administrator under UAC, whose session token is a limited token linked to an elevated one. A standard user's UAC prompt asks for another account's credentials and runs the pass as that account, whose per-user readings describe that account, so `New-ElevatedLaunch` refuses up front and the import refuses such a result. The admin token runs one shown script, and that process writes into one file the standard session created for it: it writes no other plugin state, creates no file under `<StateBase>`, and removes the copy it runs from.

1. **Prepare.** `New-ElevatedLaunch` (`scripts/windows/lib/New-ElevatedLaunch.ps1`) refuses unless the session token's elevation type is Limited, then pre-creates the empty `<StateBase>/logs/elevated-result-<runStamp>.json`, records its file ID from the creating handle, and writes `<StateBase>/logs/elevated-run-<runStamp>.ps1`: the functions of `scripts/windows/lib/Invoke-ElevatedBootstrap.ps1`, then one `Invoke-ElevatedBootstrap` call carrying the orchestrator's `-ResultPath` arguments and a manifest, the SHA-256 of each file `Get-ElevatedPassManifest` lists (the orchestrator, the lib and check scripts, `catalog/checks.jsonc` and `catalog/schemas/*.json`), read from the install tree now. It refuses a `<StateBase>` under a cloud sync root, and any path holding a control character or a single quote (`'` or U+2018 to U+201B), since each path goes into the script as a single-quoted literal.
2. **Hash check.** The launch argument string is `-NoProfile -Command` with a block that reads the script's bytes once, exits 3 without running anything when their SHA-256 is not the shown hash, and otherwise runs those same bytes as a script block. `Get-ElevatedLaunch` finds the script by that hash and reads the result path and file ID from its bootstrap call, refusing a result path other than the one the script name's stamp gives. `Start-ElevatedLaunch` passes the string to `Start-Process -Verb RunAs`, with the session's own `$PSHOME\pwsh.exe` as the file, only when it equals the string rebuilt from the script path and hash.
3. **Bootstrap.** Before any module loads, `Invoke-ElevatedBootstrap` sets `PSModulePath` to the machine-wide folders only (PowerShell 7's AllUsers folder, `$PSHOME\Modules`, then the system value's folders), and gives `Path` and each variable `HKCU\Environment` defines its system value, from `CreateEnvironmentBlock` with no user token, or removes it when the system sets none. It reads each manifest file once and exits 4, copying and running nothing, when one is missing or does not hash to its entry. Otherwise it writes the checked bytes into a new, randomly named folder under ProgramData, created owned by Administrators with access for Administrators and SYSTEM only, runs the orchestrator from that copy, and removes the folder. `Invoke-CheckWithTimeout` hands each check job the pinned `PSModulePath`, since a job's pwsh puts the user module folder back at startup. A module a check imports is therefore found only when installed for all users: the drivers check does not see a PSWindowsUpdate installed for the current user.
4. **Elevated run.** In `-ResultPath` mode the orchestrator branches before creating any directory or binding the run log. It runs only the checks with a `Get-ElevationMatrix` row, each from the script its shipped catalog entry names in the copy (the overlay under `<StateBase>` can switch a check off, never change its script), and reads mutes through `Get-MuteState` only. Each check gets its arguments and its `Get-CheckTimeoutSec` timeout as in a standard run; the command passes no `-SampleSeconds`, so the parameter's default applies. It takes no lock, writes no log, report, battery report, cache or view, and runs no remediation.
5. **Write.** `Write-ElevatedResult` opens the result file without following a reparse point at the path, refuses a handle that is not a disk file, a reparse point, or a file whose ID (64-bit volume serial, 128-bit file ID) is not the recorded one, and writes through that handle the document with `format`, `ran_at`, `elevated`, `user_sid`, `results` and `log`.
6. **Import.** A standard run with `-ElevatedResultPath` accepts the file only when `format` is `elevated-result/1`, `elevated` is `true`, `user_sid` is the importing user's, `ran_at` is later than the file's creation time (the pre-create time) and no more than `Import-ElevatedResult`'s `-MaxAge` before the import run started, and every result passes `Assert-CheckResult`. Results for ids with an elevation-matrix row replace the run's own per check id before trend analysis, and are appended when the run did not dispatch that check; others are dropped and counted in one INFO `elevated-pass` result. `latest.json` lists the imported ids in `elevated_checks`, and the document's log lines go to the run log prefixed `elevated:`. A refused file changes no result and adds one UNKNOWN `elevated-pass` result naming why.

Residual risk, accepted: three things the standard token can write still reach the elevated run.

- The pass's files as they stood at prepare time. The manifest is hashed at prepare time from the install tree, so it narrows the window between the owner's look and the copy without closing it: a file changed after prepare is refused, while one changed before prepare is hashed as it stands and runs elevated. A manifest signed at release would close it.
- The environment the elevated `pwsh` starts with, built from the user's profile. The bootstrap pins it only once it runs, so a variable that `pwsh` or its runtime reads at startup acts before the pin; and the pin replaces only `Path`, `PSModulePath` and the names `HKCU\Environment` defines.
- `pwsh` itself, when it is installed under the user profile rather than a machine-wide folder.

Nothing guards against these three.

- **Pointer**: how PowerShell 7 builds `PSModulePath` at startup, including the user folder a child pwsh adds back, is in [about_PSModulePath, "PowerShell 7 startup"](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_psmodulepath#powershell-7-startup). **As of**: 2026-10-26. **Recheck trigger**: that section changes the order or the sources it builds the value from.
- **Pointer**: what `CreateEnvironmentBlock` returns with no token is in [CreateEnvironmentBlock, `hToken`](https://learn.microsoft.com/windows/win32/api/userenv/nf-userenv-createenvironmentblock): "system variables only". **As of**: 2026-10-26. **Recheck trigger**: that parameter's description changes.
- **Pointer**: `FileSystemAclExtensions.CreateDirectory` creates the folder with the given security, and returns an existing folder unchanged, which is why the bootstrap names the folder randomly and checks its owner: [FileSystemAclExtensions.CreateDirectory](https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions.createdirectory). **As of**: 2026-10-26. **Recheck trigger**: the method's summary changes what it does with an existing folder.
- **Pointer**: where installed plugin files live is in [Plugin loading reference, "Find plugins on disk"](https://code.claude.com/docs/en/plugins/loading#find-plugins-on-disk); the page does not say who can write there. Observed on this host on 2026-10-22: the install tree sits under the user's own profile (`<home>\.claude\plugins\cache`), which the standard token can write. **As of**: 2026-10-22. **Recheck trigger**: that section moves the plugin cache out of the user profile or states its permissions.

## Adding a new admin-gated capability

1. Add a check (or extend an existing one) declaring `needs_admin: $true` via `New-HealthResult -NeedsAdmin $true`.
2. When non-elevated, call `New-HealthResult -AdminFields @('fieldA', 'fieldB')` so the report's elevation-coverage block enumerates skipped fields.
3. Add a row to `Get-ElevationMatrix.ps1` with `Feature`, `CheckId`, `Fields`, `Reason`.

## Cross-OS portability

The **concept** is shared: elevation exists on Windows, macOS, and Linux, spelled differently as admin SID, euid 0, and sudo. The **matrix data** is OS-specific. When macOS/Linux implementations land:

- `reference/macos/elevation-matrix.md`: enumerates capabilities gated on `EUID == 0` or Keychain/Authorization Services
- `reference/linux/elevation-matrix.md`: enumerates capabilities gated on `EUID == 0`, capabilities(7), or polkit

Banner renderer (`Write-ElevationBanner.ps1`) and coverage-markdown renderer (`Get-ElevationCoverageMarkdown`) are already OS-neutral; they consume whichever matrix the orchestrator loads.
