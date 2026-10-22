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

The audit session drives an optional elevated pass; when it may be offered, what the owner is shown and what counts as the owner's yes are in [SKILL.md, "Elevated pass"](../../SKILL.md#elevated-pass). This section states the mechanism. The admin token runs one shown command, and that process writes into one file the standard session created for it: it writes no other plugin state and creates no file under `<StateBase>`.

1. **Prepare.** `New-ElevatedLaunch` (`scripts/windows/lib/New-ElevatedLaunch.ps1`) pre-creates the empty `<StateBase>/logs/elevated-result-<runStamp>.json`, records its file ID from the creating handle, and writes `<StateBase>/logs/elevated-run-<runStamp>.ps1` holding one orchestrator command in `-ResultPath` mode. It refuses a `<StateBase>` under a cloud sync root, and any path holding a control character or a single quote (`'` or U+2018 to U+201B), since each path goes into the command as a single-quoted literal.
2. **Hash check.** The launch argument string is `-NoProfile -Command` with a block that reads the script's bytes once, exits 3 without running anything when their SHA-256 is not the shown hash, and otherwise runs those same bytes as a script block. `Start-ElevatedLaunch` passes it to `Start-Process pwsh -Verb RunAs` only when it equals the string rebuilt from the script path and hash.
3. **Elevated run.** In `-ResultPath` mode the orchestrator branches before creating any directory or binding the run log. It runs only the checks with a `Get-ElevationMatrix` row, each from the script its shipped catalog entry names (the overlay under `<StateBase>` can switch a check off, never change its script), and reads mutes through `Get-MuteState` only. Each check gets its arguments and its `Get-CheckTimeoutSec` timeout as in a standard run; the command passes no `-SampleSeconds`, so the parameter's default applies. It takes no lock, writes no log, report, battery report, cache or view, and runs no remediation.
4. **Write.** `Write-ElevatedResult` opens the result file without following a reparse point at the path, refuses a handle that is not a disk file, a reparse point, or a file whose ID (64-bit volume serial, 128-bit file ID) is not the recorded one, and writes through that handle the document with `format`, `ran_at`, `elevated`, `user_sid`, `results` and `log`.
5. **Import.** A standard run with `-ElevatedResultPath` accepts the file only when `format` is `elevated-result/1`, `elevated` is `true`, `user_sid` is the importing user's, `ran_at` is later than the file's creation time (the pre-create time) and every result passes `Assert-CheckResult`. Results replace the run's own per check id before trend analysis, only for ids with an elevation-matrix row; others are dropped and counted in one INFO `elevated-pass` result. `latest.json` lists the replaced ids in `elevated_checks`, and the document's log lines go to the run log prefixed `elevated:`. A refused file changes no result and adds one UNKNOWN `elevated-pass` result naming why.

Residual risk, accepted: the hash covers only the one-command script. What that command loads is writable with the standard token, so a standard-token process could change it between the owner's look and the elevated run:

- the orchestrator and lib scripts it calls, in the plugin install tree;
- PowerShell modules a check imports from user-writable module paths such as `Documents\PowerShell\Modules`;
- `HKCU\Environment` values, `PATH` and `PSModulePath` among them, which the elevated process inherits;
- which `pwsh` runs, since `Start-Process pwsh` resolves it through `PATH`.

Nothing here guards against these; the pass trusts the standard user's own profile.

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
