#Requires -Version 7.4
<#
.SYNOPSIS
Check: installed apps with no recorded launch. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#22-app-last-use for the rubric.
#>
[CmdletBinding()]
param(
    [switch]$Human,
    [string[]]$MutedKeys = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-InstalledApp.ps1')
. (Join-Path $PSScriptRoot '..\lib\Read-UserAssist.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-EvidenceWindow.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-ElevatedAppEvidence.ps1')

$id = 'app-last-use'
$category = 'config'
$commands = @(
    'Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall (also WOW6432Node and HKCU) | Get-ItemProperty'
    'Get-AppxPackage'
    'Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\*\Count'
    'Get-ChildItem $env:SystemRoot\Prefetch; Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings\<SID>'
)

# A folder this shallow ("X:\Program Files") holds many apps, so a launch under
# it says nothing about one of them.
$minimumInstallDirDepth = 2

function Get-AppLaunch {
    <#
    .SYNOPSIS
    The launch records that name one app: its packaged AppUserModelID for a
    Store app; for a Win32 app, its DisplayIcon executable or a path under its
    install folder. Returns { HasRecord, LastRun, Source }.
    #>
    param($App, [object[]] $UserAssist, [object[]] $Prefetch, [object[]] $Bam)

    $launches = [System.Collections.Generic.List[pscustomobject]]::new()
    $hasRecord = $false
    if ($App.Kind -eq 'store') {
        $prefix = "$($App.PackageFamilyName)!"
        foreach ($entry in $UserAssist) {
            if (-not $entry.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $hasRecord = $true
            if ($entry.LastRun) { $launches.Add([pscustomobject]@{ At = $entry.LastRun; Source = 'userassist' }) }
        }
    } else {
        $exe = $App.ExePath
        $dir = $null
        if ($App.InstallDir -and ($App.InstallDir.Split('\', [StringSplitOptions]::RemoveEmptyEntries).Count -gt $minimumInstallDirDepth)) {
            $dir = $App.InstallDir + '\'
        }
        $matchesApp = {
            param([string] $Path)
            if (-not $Path) { return $false }
            ($exe -and $Path -eq $exe) -or ($dir -and $Path.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase))
        }
        $hasRecord = [bool]($exe -or $dir)
        foreach ($entry in $UserAssist) {
            if ($entry.LastRun -and (& $matchesApp $entry.Path)) {
                $launches.Add([pscustomobject]@{ At = $entry.LastRun; Source = 'userassist' })
            }
        }
        # BAM paths carry no drive letter; compare from the volume root.
        $bamExe = $exe -replace '^[A-Za-z]:', ''
        $bamDir = $dir -replace '^[A-Za-z]:', ''
        foreach ($entry in $Bam) {
            if (($bamExe -and $entry.Path -eq $bamExe) -or
                ($bamDir -and $entry.Path.StartsWith($bamDir, [StringComparison]::OrdinalIgnoreCase))) {
                $launches.Add([pscustomobject]@{ At = $entry.LastRun; Source = 'bam' })
            }
        }
        if ($exe) {
            $exeName = [System.IO.Path]::GetFileName($exe)
            foreach ($entry in $Prefetch) {
                if ($entry.ExeName -eq $exeName) { $launches.Add([pscustomobject]@{ At = $entry.LastRun; Source = 'prefetch' }) }
            }
        }
    }

    $latest = $launches | Sort-Object At -Descending | Select-Object -First 1
    return [pscustomobject]@{
        HasRecord = $hasRecord
        LastRun   = $latest ? $latest.At : $null
        Source    = $latest ? $latest.Source : $null
    }
}

$FailureSummary = 'App last-use check failed.'
$PassThru = $false
$CheckBody = {
    $window = Get-EvidenceWindow
    $installed = Get-InstalledApp
    $userAssist = Read-UserAssist
    $elevated = @(Get-ElevatedAppEvidence)
    $prefetch = $elevated | Where-Object Source -EQ 'prefetch'
    $bam = $elevated | Where-Object Source -EQ 'bam'

    $uaEntries = $userAssist.ReadState -eq 'ok' ? @($userAssist.Entries) : @()
    $since = $window.Start ? $window.Start.ToString('yyyy-MM-dd') : $null
    $noLaunchText = $since ? "no launch recorded since $since" : 'no launch recorded'

    $items = [System.Collections.Generic.List[pscustomobject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($app in @($installed.Apps | Sort-Object Name)) {
        if (-not $seen.Add($app.Key)) { continue }
        $launch = Get-AppLaunch -App $app -UserAssist $uaEntries -Prefetch @($prefetch.Entries) -Bam @($bam.Entries)

        # Without a readable UserAssist, or with nothing that could name the app
        # in it, a missing launch is no evidence either way.
        $verdict = if ($launch.LastRun) {
            'launched'
        } elseif ($userAssist.ReadState -eq 'ok' -and $launch.HasRecord) {
            'no-launch-recorded'
        } else {
            'no-evidence'
        }
        $status = switch ($verdict) {
            'launched' { "last launch $($launch.LastRun.ToString('yyyy-MM-dd'))" }
            'no-launch-recorded' { $noLaunchText }
            default { 'no launch evidence' }
        }
        $items.Add((New-FindingItem -Kind 'app' -Identity @($app.Key) -MutedKeys $MutedKeys `
                    -Severity ($verdict -eq 'launched' ? 'OK' : 'INFO') -Title "$($app.Name): $status" -Fields @{
                    name               = $app.Name
                    app_kind           = $app.Kind
                    install_date       = $app.InstallDate ? $app.InstallDate.ToString('yyyy-MM-dd') : $null
                    last_launch        = $launch.LastRun ? $launch.LastRun.ToString('o') : $null
                    last_launch_source = $launch.Source
                    verdict            = $verdict
                }))
    }

    $launchedCount = @($items | Where-Object verdict -EQ 'launched').Count
    $noLaunchCount = @($items | Where-Object verdict -EQ 'no-launch-recorded').Count
    $noEvidenceCount = @($items | Where-Object verdict -EQ 'no-evidence').Count
    $readStates = @($window.ReadState, $installed.ReadState, $userAssist.ReadState, $prefetch.ReadState, $bam.ReadState)

    $severity = Get-UnmutedSeverity -Items $items.ToArray() -ReadState $readStates
    # Every verdict rests on UserAssist; an unreadable one leaves the list unjudged.
    if (-not (Test-ReadStateUsable $userAssist.ReadState)) { $severity = 'UNKNOWN' }
    $summary = ("$noLaunchCount of $($items.Count) installed app(s): $noLaunchText. " +
        "$launchedCount launched; $noEvidenceCount without launch evidence.")
    if ($userAssist.ReadState -ne 'ok') { $summary += " UserAssist launch records: $($userAssist.ReadState)." }

    # Prefetch and BAM refuse a standard token; their fields fill only when elevated.
    $adminFields = @(
        if ($prefetch.ReadState -eq 'denied') { 'prefetch_state' }
        if ($bam.ReadState -eq 'denied') { 'bam_state' }
    )

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands -Detail @{
        items             = $items.ToArray()
        items_count       = $items.Count
        muted_count       = @($items | Where-Object { $_.muted }).Count
        evidence_start    = $window.Start ? $window.Start.ToString('o') : $null
        evidence_days     = $window.Days
        apps_count        = $items.Count
        launched_count    = $launchedCount
        no_launch_count   = $noLaunchCount
        no_evidence_count = $noEvidenceCount
        userassist_state  = $userAssist.ReadState
        prefetch_state    = $prefetch.ReadState
        bam_state         = $bam.ReadState
        apps_state        = $installed.ReadState
        evidence_state    = $window.ReadState
    } `
        -AdminFields $adminFields `
        -NeedsAdmin $false -RanSuccessfully $true
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
