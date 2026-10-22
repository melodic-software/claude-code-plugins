#Requires -Version 7.4

<#
.SYNOPSIS
Build the RunSnapshot the orchestrator writes to latest.json and prints on
stdout.

.DESCRIPTION
Shape: reference/shared/output-schema.md, "RunSnapshot". Every required field
is always present, so a run that stops early (a held run.lock) still emits a
complete snapshot: empty arrays and duration_seconds 0 by default. The run's
artifact fields (run_stamp, report_path, page_path) are null when not given.
#>

function New-RunSnapshot {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object; changes no system state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)] [string] $RunId,
        [Parameter(Mandatory = $true)] [string] $HostName,
        [Parameter(Mandatory = $true)] [string] $OsVersion,
        [Parameter(Mandatory = $true)] [bool] $Elevated,
        [Parameter(Mandatory = $true)] [string] $RunMode,
        [Parameter(Mandatory = $true)] [bool] $DryRun,
        [AllowEmptyCollection()] [object[]] $Checks = @(),
        [AllowEmptyCollection()] [object[]] $Remediations = @(),
        [AllowEmptyCollection()] [object[]] $DiscoveredChecks = @(),
        [AllowEmptyCollection()] [string[]] $UrlsCalled = @(),
        [double] $DurationSeconds = 0,
        [string] $RunStamp,
        [string] $ReportPath,
        [string] $PagePath,
        [int] $CadenceDeferredCount = 0
    )

    return [ordered]@{
        run_id             = $RunId
        hostname           = $HostName
        os                 = 'windows'
        os_version         = $OsVersion
        elevated           = $Elevated
        run_mode           = $RunMode
        dry_run            = $DryRun
        powershell_version = $PSVersionTable.PSVersion.ToString()
        checks             = @($Checks)
        remediations       = @($Remediations)
        discovered_checks  = @($DiscoveredChecks)
        urls_called        = @($UrlsCalled)
        duration_seconds   = $DurationSeconds
        run_stamp          = $RunStamp ? $RunStamp : $null
        report_path        = $ReportPath ? $ReportPath : $null
        page_path          = $PagePath ? $PagePath : $null
        cadence_deferred_count = $CadenceDeferredCount
    }
}
