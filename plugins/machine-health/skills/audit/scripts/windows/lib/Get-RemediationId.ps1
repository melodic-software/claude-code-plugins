#Requires -Version 7.4

<#
.SYNOPSIS
Return the ids of the shipped remediations, derived from the scripts in
scripts/windows/remediations/.

.DESCRIPTION
Each remediation script is named after its id in PascalCase
(Clear-TempFiles.ps1 is clear-temp-files), so adding a remediation script adds
its id here with no list to keep in step.
#>

function Get-RemediationId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $RemediationsDir = (Join-Path $PSScriptRoot '..\remediations')
    )

    Get-ChildItem -LiteralPath $RemediationsDir -Filter '*.ps1' -File |
        Sort-Object Name |
        ForEach-Object { ($_.BaseName -creplace '(?<=[a-z0-9])(?=[A-Z])', '-').ToLowerInvariant() }
}
