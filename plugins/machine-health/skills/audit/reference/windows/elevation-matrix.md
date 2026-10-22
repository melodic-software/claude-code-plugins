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

The audit session drives an optional elevated pass (SKILL.md, "Elevated pass"). The admin token runs one shown command, and that process writes into one file the standard session created for it. It writes no other plugin state and creates no file under `<StateBase>`.

1. **Prepare.** The session calls `New-ElevatedLaunch` (`scripts/windows/lib/New-ElevatedLaunch.ps1`). It pre-creates the empty `<StateBase>/logs/elevated-result-<runStamp>.json` and records its file ID (volume serial plus file index), writes `<StateBase>/logs/elevated-run-<runStamp>.ps1` holding one command, and returns `{ ScriptPath, ScriptSha256, ResultPath, ResultFileId, ArgumentString }`. The command is:

   ```powershell
   & '<skill-root>\scripts\windows\Invoke-MachineHealthCheck.ps1' -OutputBase '<OutputBase>' -StateBase '<StateBase>' -RunMode on-demand -SkipBanner -ResultPath '<result file>' -ResultFileId '<file id>'
   ```

   A `<StateBase>` under a cloud sync root is refused, as every other state write is.
2. **Ask.** The session shows the script and its SHA-256 in full and launches only after the owner's explicit yes in that session. It never offers the pass under `--scheduled`.
3. **Launch.** `Start-Process pwsh -Verb RunAs -Wait -ArgumentList '<ArgumentString>'`; the owner approves the UAC prompt. The argument string is `-NoProfile -Command` with a block that reads the script's bytes once, exits 3 without running anything when their SHA-256 is not the shown hash, and otherwise runs those same bytes as a script block. The hash is on the command line the owner approves.
4. **Elevated run.** In `-ResultPath` mode the orchestrator branches before creating any directory or binding the run log. It runs only the checks with a `Get-ElevationMatrix` row, each from the script its shipped catalog entry names (the overlay under `<StateBase>` can switch a check off, never change its script), and reads mutes through `Get-MuteState` only. It takes no lock and writes no log, report, battery report, cache or view, and runs no remediation. `Write-ElevatedResult` opens the result file without following reparse points, refuses a reparse point, a directory or a file ID other than `-ResultFileId`, and writes through that handle `{ "format": "elevated-result/1", "ran_at": "<ISO>", "elevated": <bool>, "results": [<CheckResult>...], "log": ["<line>"...] }`.
5. **Import.** A standard run with `-ElevatedResultPath '<result file>'` accepts the file only when `format` matches, `ran_at` is later than the file's creation time (the pre-create time) and every result passes `Assert-CheckResult`. Its results replace the run's own per check id before trend analysis, and `latest.json` lists those ids in `elevated_checks`. A refused file changes no result and adds one UNKNOWN `elevated-pass` result naming why.

Residual risk, accepted: the hash covers only the one-command script. The orchestrator and lib scripts it calls sit in the plugin install tree, which the standard user can write, so a process running with the standard token could change them between the owner's look and the elevated run.

## Adding a new admin-gated capability

1. Add a check (or extend an existing one) declaring `needs_admin: $true` via `New-HealthResult -NeedsAdmin $true`.
2. When non-elevated, call `New-HealthResult -AdminFields @('fieldA', 'fieldB')` so the report's elevation-coverage block enumerates skipped fields.
3. Add a row to `Get-ElevationMatrix.ps1` with `Feature`, `CheckId`, `Fields`, `Reason`.

## Cross-OS portability

The **concept** is shared: elevation exists on Windows, macOS, and Linux, spelled differently as admin SID, euid 0, and sudo. The **matrix data** is OS-specific. When macOS/Linux implementations land:

- `reference/macos/elevation-matrix.md`: enumerates capabilities gated on `EUID == 0` or Keychain/Authorization Services
- `reference/linux/elevation-matrix.md`: enumerates capabilities gated on `EUID == 0`, capabilities(7), or polkit

Banner renderer (`Write-ElevationBanner.ps1`) and coverage-markdown renderer (`Get-ElevationCoverageMarkdown`) are already OS-neutral; they consume whichever matrix the orchestrator loads.
