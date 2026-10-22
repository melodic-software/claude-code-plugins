#Requires -Version 7.4

<#
.SYNOPSIS
Build the run's decision page, prune older runs' pages after a successful
build, and note the outcome in the markdown report.

.DESCRIPTION
The orchestrator calls this after it writes the report. node runs
scripts/build-checkup-view.mjs over latest.json into <StateBase>/views. Only
when that build exits Ok are older runs' pages pruned (Remove-OldCheckupView,
by exact path); node missing or a failed build leaves every older page in
place. Each outcome is logged and appended to the report under
"## Decision page".

A synced StateBase has no latest.json, so -StateWritable $false builds
nothing, prunes nothing and leaves the report alone.

Returns the page path when a page was built, else nothing.
#>

. (Join-Path $PSScriptRoot 'Invoke-NativeCommand.ps1')
. (Join-Path $PSScriptRoot 'Get-RemediationId.ps1')
. (Join-Path $PSScriptRoot 'Remove-OldCheckupView.ps1')
. (Join-Path $PSScriptRoot 'Write-MachineHealthLog.ps1')

function Publish-CheckupView {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [bool] $StateWritable,
        [Parameter(Mandatory = $true)] [string] $StateBase,
        [Parameter(Mandatory = $true)] [string] $LatestPath,
        [Parameter(Mandatory = $true)] [string] $RunStamp,
        [Parameter(Mandatory = $true)] [string] $ReportPath
    )

    if (-not $StateWritable) { return }
    $viewsDir = Join-Path $StateBase 'views'
    New-Item -ItemType Directory -Path $viewsDir -Force | Out-Null
    $build = Invoke-NativeCommand -Name 'node' -ArgumentList @(
        (Join-Path $PSScriptRoot '..\..\build-checkup-view.mjs'), '--latest', $LatestPath, '--views-dir', $viewsDir,
        '--run-stamp', $RunStamp, '--remediations', (@(Get-RemediationId) -join ','))
    $pagePath = $null
    $pageNote = switch ($build.status) {
        'Absent' {
            Write-MachineHealthLog 'checkup_view_skipped node_missing'
            '_No decision page: Node.js was not found, so this markdown report is the only output._'
        }
        'Ok' {
            $pagePath = Join-Path $viewsDir "checkup-$RunStamp.html"
            Write-MachineHealthLog "checkup_view_built path=$pagePath"
            try {
                $pruned = @(Remove-OldCheckupView -ViewsDir $viewsDir -CurrentStamp $RunStamp)
                Write-MachineHealthLog "checkup_view_pruned files=$($pruned.Count)"
            } catch {
                Write-MachineHealthLog "checkup_view_prune_failed $($_.Exception.Message)"
            }
            "Open ``$pagePath`` to mute items or approve remediations, then paste its picks into ``/machine-health:setup picks``."
        }
        default {
            Write-MachineHealthLog ("checkup_view_failed status=$($build.status) exit=$($build.exit_code) " +
                ("$($build.output) $($build.error)" -replace '\s+', ' ').Trim())
            '_No decision page: the page build failed; see the run log._'
        }
    }
    Add-Content -LiteralPath $ReportPath -Value "`n## Decision page`n`n$pageNote" -Encoding utf8
    $pagePath
}
