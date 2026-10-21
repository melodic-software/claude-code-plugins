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
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-DefenderExclusionState.ps1')

$id = 'defender-exclusions'
$category = 'security'
$commands = @(
    "Get-CimInstance -Namespace $script:DefenderPreferenceNamespace -ClassName $script:DefenderPreferenceClass | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess"
)

# Well-known benign exclusions common on dev machines (.NET, Node, Python
# test runners, build caches). The aim is to WARN only on unexpected entries.
$knownSafePaths = @(
    '*\NuGetScratch*'
    '*\node_modules*'
    '*\.dotnet*'
    '*\dotnet-install*'
    '*\.cache*'
    '*\Visual Studio\Packages*'
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
            foreach ($entry in @(
                    @{ Type = 'path'; Values = $state.Paths }
                    @{ Type = 'extension'; Values = $state.Extensions }
                    @{ Type = 'process'; Values = $state.Processes }
                )) {
                foreach ($value in $entry.Values) {
                    $expected = $false
                    if ($entry.Type -eq 'path') {
                        foreach ($pattern in $knownSafePaths) {
                            if ($value -like $pattern) { $expected = $true; break }
                        }
                    }
                    # Extension and process exclusions have no known-safe list and stay INFO.
                    $itemSeverity = $entry.Type -eq 'path' -and -not $expected ? 'WARN' : 'INFO'
                    $items.Add((New-FindingItem -Kind 'exclusion' -Identity @($entry.Type, $value) -MutedKeys $MutedKeys `
                                -Severity $itemSeverity -Title "$($entry.Type) exclusion: $value" -Fields @{
                                exclusion_type = $entry.Type
                                value          = $value
                                expected       = $expected
                            }))
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
                unexpected_paths          = @($unexpectedPaths | Select-Object -First 20)
                list_state                = $state.ReadState
                items_count               = $items.Count
                muted_count               = @($items | Where-Object muted).Count
                items                     = $items.ToArray()
            } `
                -NeedsAdmin $true -RanSuccessfully $true
        }
        'masked' {
            # Defender answers a standard user with a placeholder, not the
            # lists: the reading is unknown, never "no exclusions".
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
