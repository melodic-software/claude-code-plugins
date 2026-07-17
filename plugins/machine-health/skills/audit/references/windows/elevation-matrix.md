# Elevation matrix — Windows

SSOT for which Windows capabilities the skill can and cannot exercise when the process is not Administrator. Structured form lives in `scripts/windows/lib/Get-ElevationMatrix.ps1` — when adding an admin-gated signal, update both files.

## Policy

- **Admin is never assumed.** Orchestrator detects elevation via `Test-IsElevated.ps1` (Win32 SID lookup) and runs unconditionally — no UAC prompt.
- **Non-elevated runs emit UNKNOWN** for gated signals with `needs_admin: true` in the check result, plus `detail.admin_fields` listing fields that would have been populated.
- **Loud upfront communication, no interactive prompts.** Pre-run banner enumerates admin-only capabilities and tells the user how to re-run elevated. SKILL.md bans y/n prompts; user either acts on the banner or lets skill continue with reduced coverage.
- **Suppress via `-SkipBanner`** for scripted/scheduled invocations.

## Capabilities that require elevation

| Feature | Check | Fields populated when elevated | Reason |
|---|---|---|---|
| SMART disk reliability counters | `disk-space` | `temp_c`, `wear_pct`, `read_errors`, `write_errors` | `Get-StorageReliabilityCounter` requires admin on most drives (NVMe/SATA alike). Non-elevated returns empty counters silently. |
| Windows Update driver catalog | `drivers` | `pending_driver_updates` | PSWindowsUpdate's `Get-WindowsUpdate -Category Drivers` wraps Windows Update Agent COM API, requiring admin for elevation-sensitive calls. |
| pnputil device problem codes | `drivers` | `problem_devices` | `pnputil /enum-devices /problem` lists devices with non-zero problem codes (10/28/43/45). Admin-only for complete output. |
| TPM + BitLocker status | `tpm-bitlocker` | `tpm_owned`, `tpm_enabled`, `bitlocker_protection_status` | `Get-Tpm` + `Get-BitLockerVolume` require admin. |

## How to run elevated

From an elevated Windows Terminal or PowerShell session:

```powershell
pwsh -NoProfile -File '<skill-root>\scripts\windows\Invoke-MachineHealthCheck.ps1' `
     -OutputBase '<OutputBase>'
```

Or schedule the weekly task to run as `SYSTEM` / an admin account — out of scope for this skill (see SKILL.md "Not in scope for this skill"), but conventional long-term answer for recurring coverage.

## Adding a new admin-gated capability

1. Add a check (or extend an existing one) declaring `needs_admin: $true` via `New-HealthResult -NeedsAdmin $true`.
2. When non-elevated, call `New-HealthResult -AdminFields @('fieldA', 'fieldB')` so the report's elevation-coverage block enumerates skipped fields.
3. Add a row to `Get-ElevationMatrix.ps1` with `Feature`, `CheckId`, `Fields`, `Reason`.
4. Add a row to the table above with same fields.

Banner and report pull from `Get-ElevationMatrix.ps1`; table above is prose counterpart. Drift check: row counts should match.

## Cross-OS portability

The **concept** is shared (elevation exists on Windows, macOS, Linux — spelled differently: admin SID, euid 0, sudo). The **matrix data** is OS-specific. When macOS/Linux implementations land:

- `references/macos/elevation-matrix.md` — enumerates capabilities gated on `EUID == 0` or Keychain/Authorization Services
- `references/linux/elevation-matrix.md` — enumerates capabilities gated on `EUID == 0`, capabilities(7), or polkit

Banner renderer (`Write-ElevationBanner.ps1`) and coverage-markdown renderer (`Get-ElevationCoverageMarkdown`) are already OS-neutral; they consume whichever matrix the orchestrator loads.
