#Requires -Version 7.4
<#
.SYNOPSIS
Check: Windows Defender exclusion audit. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#11-defender-exclusions for rubric.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MutedKeys',
    Justification = 'Read inside $CheckBody, which Invoke-HealthCheckEnvelope invokes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'result',
    Justification = 'Set inside $CheckBody and read by Invoke-HealthCheckEnvelope.')]
param(
    [switch]$Human,
    [string[]]$MutedKeys = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Test-IsElevated.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-DefenderExclusionItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-DefenderExclusionState.ps1')

$id = 'defender-exclusions'
$category = 'security'
$commands = @(
    "Get-CimInstance -Namespace $script:DefenderPreferenceNamespace -ClassName $script:DefenderPreferenceClass | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess"
)

$adminFieldList = @(
    'exclusion_path_count'
    'exclusion_extension_count'
    'exclusion_process_count'
    'unexpected_path_count'
)

# Outer-catch fallback must keep admin-gate metadata so unexpected
# failures don't get misclassified as non-admin downstream.
$FailureSummary = 'Defender exclusion check failed.'
$PassThru = $false
$FailureNeedsAdmin = $true
$FailureAdminFields = $adminFieldList
$CheckBody = {
    $state = Get-DefenderExclusionState
    $emptyList = @{ list_state = $state.ReadState; items_count = 0; muted_count = 0; items = @() }

    switch ($state.ReadState) {
        'ok' {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($listName in $script:DefenderExclusionTypes.Keys) {
                $type = $script:DefenderExclusionTypes[$listName]
                foreach ($value in $state.$listName) {
                    # Extension and process exclusions have no known-safe list and stay INFO.
                    $expected = $type -eq 'path' -and (Test-DefenderKnownSafePath -Path $value)
                    $itemSeverity = $type -eq 'path' -and -not $expected ? 'WARN' : 'INFO'
                    $items.Add((New-DefenderExclusionItem -Type $type -Value $value -MutedKeys $MutedKeys `
                                -Severity $itemSeverity -Title "$type exclusion: $value" -Fields @{ expected = $expected }))
                }
            }

            # A muted item counts as expected.
            $unexpectedPaths = @($items | Where-Object { $_.exclusion_type -eq 'path' -and -not $_.expected -and -not $_.muted } |
                    ForEach-Object { $_.value })
            $severity = Get-UnmutedSeverity -Items $items.ToArray()
            $summary = "$(@($state.Paths).Count) path exclusion(s), $(@($state.Extensions).Count) extension(s), $(@($state.Processes).Count) process(es)."
            if ($unexpectedPaths.Count -gt 0) {
                $summary = "$($unexpectedPaths.Count) unexpected Defender path exclusion(s)."
            }

            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity $severity -Summary $summary -Commands $commands `
                -Detail @{
                exclusion_path_count      = @($state.Paths).Count
                exclusion_extension_count = @($state.Extensions).Count
                exclusion_process_count   = @($state.Processes).Count
                unexpected_path_count     = $unexpectedPaths.Count
                # Objects, not strings, so the markdown report shows a count, never a value.
                unexpected_paths          = @($unexpectedPaths | Select-Object -First 20 | ForEach-Object { [pscustomobject]@{ path = $_ } })
                list_state                = $state.ReadState
                items_count               = $items.Count
                muted_count               = @($items | Where-Object muted).Count
                items                     = $items.ToArray()
            } `
                -NeedsAdmin $true -RanSuccessfully $true
        }
        'masked' {
            # Unknown, never "no exclusions" (see Get-DefenderExclusionState.ps1).
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'UNKNOWN' `
                -Summary 'Defender exclusion lists are masked (re-run elevated).' `
                -Detail (@{ elevated = [bool](Test-IsElevated) } + $emptyList) `
                -Commands $commands `
                -NeedsAdmin $true -RanSuccessfully $false `
                -ErrorMessage 'needs_admin' `
                -AdminFields $adminFieldList
        }
        default {
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'UNKNOWN' -Summary 'Defender exclusion lists unavailable (third-party AV?).' `
                -Detail $emptyList `
                -Commands $commands -RanSuccessfully $false `
                -NeedsAdmin $true `
                -ErrorMessage "Defender preference read state '$($state.ReadState)'." `
                -AdminFields $adminFieldList
        }
    }
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
