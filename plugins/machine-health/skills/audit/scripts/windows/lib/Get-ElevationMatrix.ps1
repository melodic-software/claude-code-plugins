#Requires -Version 7.4

<#
.SYNOPSIS
Returns the structured elevation-awareness matrix for Windows: which
operations require admin and what fields they populate.

.DESCRIPTION
Data is the source of truth for the pre-run elevation banner and the report
header coverage block. Each entry describes one capability that degrades
when the skill runs non-elevated:

  Feature       : human-readable name of the capability
  CheckId       : catalog check that consumes this capability (for cross-ref)
  AdminRequired : always $true for Windows entries
  Fields        : detail-key names the check populates only when elevated
  Reason        : why elevation is required (API/permission note)

When a new admin-gated check lands, it MUST add an entry here. The banner
surfaces these; the report `{{elevation_coverage}}` token renders them.

Windows-specific by design. Parallel macos/elevation-matrix.ps1 and
linux/elevation-matrix.ps1 files will appear when those OS implementations
land. The banner renderer (Write-ElevationBanner.ps1) is OS-agnostic and
consumes whichever matrix file the orchestrator loads.
#>

function Get-ElevationMatrix {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    return @(
        [pscustomobject]@{
            Feature       = 'SMART disk reliability counters (temp / wear)'
            CheckId       = 'disk-space'
            AdminRequired = $true
            Fields        = @('temp_c', 'wear_pct', 'read_errors', 'write_errors')
            Reason        = 'Get-StorageReliabilityCounter requires admin on most drives.'
        }
        [pscustomobject]@{
            Feature       = 'Windows Update driver catalog query'
            CheckId       = 'drivers'
            AdminRequired = $true
            Fields        = @('pending_driver_updates')
            Reason        = 'PSWindowsUpdate Get-WindowsUpdate requires admin + WUA COM.'
        }
        [pscustomobject]@{
            Feature       = 'pnputil device problem codes'
            CheckId       = 'drivers'
            AdminRequired = $true
            Fields        = @('problem_devices')
            Reason        = 'pnputil /enum-devices /problem requires admin for full output.'
        }
        [pscustomobject]@{
            Feature       = 'TPM ownership + BitLocker volume status'
            CheckId       = 'tpm-bitlocker'
            AdminRequired = $true
            Fields        = @('tpm_owned', 'tpm_enabled', 'bitlocker_protection_status')
            Reason        = 'Get-Tpm + Get-BitLockerVolume require admin.'
        }
        [pscustomobject]@{
            Feature       = 'Windows Defender exclusion list audit'
            CheckId       = 'defender-exclusions'
            AdminRequired = $true
            Fields        = @(
                'exclusion_path_count'
                'exclusion_extension_count'
                'exclusion_process_count'
                'unexpected_path_count'
            )
            Reason        = 'Get-MpPreference returns a placeholder string for exclusion fields when non-elevated.'
        }
        [pscustomobject]@{
            Feature       = 'Complete logon-task inventory'
            CheckId       = 'startup-items'
            AdminRequired = $true
            Fields        = @('tasks_complete')
            Reason        = 'Get-ScheduledTask lists only part of the task store to a standard token.'
        }
        [pscustomobject]@{
            Feature       = 'Prefetch and BAM launch records'
            CheckId       = 'app-last-use'
            AdminRequired = $true
            Fields        = @('prefetch_state', 'bam_state')
            Reason        = 'The Prefetch folder and the BAM registry key refuse a standard token.'
        }
        [pscustomobject]@{
            Feature       = 'Restore points and system image versions'
            CheckId       = 'backup-status'
            AdminRequired = $true
            Fields        = @('restore_points', 'system_image')
            Reason        = 'The SystemRestore CIM class and wbadmin get versions refuse a non-elevated caller.'
        }
    )
}
