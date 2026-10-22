#Requires -Version 7.4

<#
.SYNOPSIS
Build the UNKNOWN CheckResult the orchestrator and the elevated-pass import
report when a check, or a step standing in for one, produced no reading.

.DESCRIPTION
-Entry supplies id, category and needs_admin (a catalog entry or a small
object with those three). The result has ran_successfully false and the
-ErrorReason as error, so it passes Assert-CheckResult. -Detail defaults to
an empty object.
#>

function New-UnknownCheckResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory result object; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [string] $Summary,
        [Parameter(Mandatory)] [string] $ErrorReason,
        [int] $DurationMs = 0,
        [AllowNull()] $Detail = $null
    )
    return [pscustomobject]@{
        id               = $Entry.id
        category         = $Entry.category
        os               = 'windows'
        ran_at           = (Get-Date).ToString('o')
        severity         = 'UNKNOWN'
        summary          = $Summary
        detail           = if ($null -eq $Detail) { @{} } else { $Detail }
        commands         = @()
        needs_admin      = [bool]$Entry.needs_admin
        ran_successfully = $false
        duration_ms      = $DurationMs
        trend            = $null
        notes            = $null
        error            = $ErrorReason
    }
}
