#Requires -Version 7.4
<#
.SYNOPSIS
machine-health orchestrator for Windows. Dispatches catalog checks, applies trend-aware
severity adjustments, runs authorized remediations, writes run state, and renders the report.

.DESCRIPTION
Requires PowerShell 7.4+ (enforced by the #Requires above; the orchestrator and checks use
7.x-only syntax). Individual checks that need a still-newer cmdlet return UNKNOWN cleanly
rather than aborting the run.

Responsibilities (per SKILL.md High-level procedure):
 1. Verify preconditions (PS version, output writable, elevation recorded).
 2. Load catalog; filter to enabled, non-deprecated entries with os: ["windows"].
 3. Load trend context from state/history.jsonl (last 8 weeks).
 4. Dispatch each check with a 90s timeout (Start-Job).
 5. Adjust severities based on trend when a threshold was just crossed.
 6. On non-dry runs: dispatch authorized remediations (TODO.md approvals + user-load heuristic).
 7. Write state/latest.json; append one compact line to state/history.jsonl.
 8. Render a markdown report from references/shared/report-template.md.
 9. Return the full run snapshot as JSON on stdout (unless -Human is set).

.PARAMETER OutputBase
Root folder for reports/. Created on first run.

.PARAMETER StateBase
Root folder for state/ and logs/ (history, approvals, run logs). Resolution:
explicit parameter, then the CLAUDE_PLUGIN_DATA environment variable (the
per-plugin data directory that survives plugin updates), then OutputBase.

.PARAMETER RunMode
weekly | on-demand | first-run. first-run forces DryRun = $true.

.PARAMETER DryRun
Skip all remediations; still produce a full report.

.PARAMETER Human
Print a human-readable summary instead of emitting the run snapshot JSON.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $OutputBase,
    [string] $StateBase,
    [ValidateSet('weekly', 'on-demand', 'first-run')] [string] $RunMode = 'weekly',
    [switch] $DryRun,
    [switch] $Human,
    [switch] $Force,
    [switch] $SkipBanner
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'

$skillRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
$libRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libRoot 'Write-MachineHealthLog.ps1')
. (Join-Path $libRoot 'Test-IsElevated.ps1')
. (Join-Path $libRoot 'Read-HistoryJsonl.ps1')
. (Join-Path $libRoot 'ConvertFrom-Jsonc.ps1')
. (Join-Path $libRoot 'Assert-CatalogEntry.ps1')
. (Join-Path $libRoot 'Get-ApprovalState.ps1')
. (Join-Path $libRoot 'Invoke-AllowlistedWeb.ps1')
. (Join-Path $libRoot 'Get-ElevationMatrix.ps1')
. (Join-Path $libRoot 'Write-ElevationBanner.ps1')
. (Join-Path $libRoot 'ConvertTo-TopMetrics.ps1')
. (Join-Path $libRoot 'Invoke-TrendAnalysis.ps1')
. (Join-Path $libRoot 'Get-RunDelta.ps1')
. (Join-Path $libRoot 'Invoke-Discovery.ps1')
. (Join-Path $libRoot 'Get-WindowsDiscoveryProbes.ps1')
. (Join-Path $libRoot 'ConvertTo-AppendixMarkdown.ps1')
. (Join-Path $libRoot 'Invoke-FindingCorrelation.ps1')
. (Join-Path $libRoot 'Merge-CatalogOverlay.ps1')
. (Join-Path $libRoot 'Get-CheckSelection.ps1')
. (Join-Path $libRoot 'Get-CheckArgument.ps1')

$runStart = Get-Date
$runId = $runStart.ToString('o')
$runDate = $runStart.ToString('yyyy-MM-dd')
# Filesystem-safe UTC run stamp for per-run artifact names (colons are invalid
# in Windows paths). Distinguishes multiple runs on the same calendar day.
$runStamp = $runStart.ToUniversalTime().ToString('yyyy-MM-ddTHHmmssZ')
$hostname = [System.Net.Dns]::GetHostName()

# Normalize and prepare output roots. Reports are user-facing and live under
# OutputBase; state and logs are machine state and live under StateBase.
$OutputBase = [System.IO.Path]::GetFullPath($OutputBase)
if ([string]::IsNullOrWhiteSpace($StateBase)) {
    $StateBase = if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_PLUGIN_DATA)) {
        $env:CLAUDE_PLUGIN_DATA
    } else {
        $OutputBase
    }
}
$StateBase = [System.IO.Path]::GetFullPath($StateBase)
$reportsDir = Join-Path $OutputBase 'reports'
$stateDir = Join-Path $StateBase 'state'
$logsDir = Join-Path $StateBase 'logs'
foreach ($d in @($OutputBase, $StateBase, $reportsDir, $stateDir, $logsDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$runLog = Join-Path $logsDir "run-$runDate.log"
$remedLog = Join-Path $logsDir "remediation-$runDate.log"

# Bind LogPath once for the 30+ orchestrator-local Write-MachineHealthLog calls below.
$PSDefaultParameterValues['Write-MachineHealthLog:LogPath'] = $runLog

Write-MachineHealthLog ("run_start run_id=$runId mode=$RunMode dry_run=$($DryRun.IsPresent) " +
    "output_base=$OutputBase state_base=$StateBase")

# Operator-facing banner: blank line, message lines, blank line. stderr keeps
# stdout clean for the JSON snapshot.
function Write-StderrBanner {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string[]] $Line)

    [Console]::Error.WriteLine('')
    foreach ($l in $Line) { [Console]::Error.WriteLine($l) }
    [Console]::Error.WriteLine('')
}

# Guard: the checked-in catalog/cisa-kev.json is a seed STUB only. If the file
# on disk is larger than the stub (which would mean machine-refreshed live data
# has contaminated source control), warn loudly. Never mutate automatically --
# the user decides whether to `git checkout -- catalog/cisa-kev.json`.
$seedKevPath = Join-Path $skillRoot 'catalog\cisa-kev.json'
if (Test-Path -LiteralPath $seedKevPath) {
    try {
        $seedSize = (Get-Item -LiteralPath $seedKevPath).Length
        if ($seedSize -gt 4096) {
            $msg = ('machine-specific state leaked: catalog/cisa-kev.json is ' +
                "$seedSize bytes (the shipped stub should be <1KB). Restore the " +
                'stub from source control, or reinstall/update the plugin.')
            Write-MachineHealthLog "kev_seed_contaminated size=$seedSize mode=$RunMode"
            Write-StderrBanner -Line "[machine-health] WARNING: $msg"
            # weekly and on-demand runs must not silently proceed past a
            # contaminated seed -- CI or a scheduled task would bury the
            # stderr banner. first-run keeps the soft warning so a new
            # operator can see the banner and repair before the first
            # real run.
            if ($RunMode -ne 'first-run') {
                Write-Output ('[machine-health] FATAL: catalog/cisa-kev.json ' +
                    "is $seedSize bytes (the shipped stub should be <1KB). Restore " +
                    'the stub from source control, or reinstall/update the plugin.')
                exit 2
            }
        }
    } catch {
        Write-MachineHealthLog "kev_seed_size_check_failed $($_.Exception.Message)"
    }
}

# first-run forces DryRun
$effectiveDry = $DryRun.IsPresent -or ($RunMode -eq 'first-run')
if ($effectiveDry -and -not $DryRun.IsPresent) {
    Write-MachineHealthLog 'dry_run forced by RunMode=first-run'
}

$elevated = Test-IsElevated

# Pre-run elevation banner (stderr only; stdout remains clean JSON).
# Non-elevated + no -SkipBanner => print the coverage matrix so the user
# knows up-front what will be degraded and how to re-run with admin.
try {
    $matrix = @(Get-ElevationMatrix)
    $nonElevatedCoverage = @(
        'disk space (used %, free GB, volume health)'
        'services state (Automatic services stopped)'
        'event log errors (BugCheck, Kernel-Power 41, WUClient, disk)'
        'Windows Update pending-reboot signals'
        'Defender status (signatures, RTP, tamper protection)'
        'winget upgrades (CISA KEV correlation)'
        'battery health (laptop only)'
        'driver inventory + signing + CodeIntegrity rejections'
        'reliability monitor score'
    )
    Write-ElevationBanner `
        -Elevated $elevated `
        -HostName $hostname `
        -UserName ("$env:USERDOMAIN\$env:USERNAME") `
        -OutputBase $OutputBase `
        -StateBase $StateBase `
        -SkillRoot $skillRoot `
        -Matrix $matrix `
        -NonElevatedCoverage $nonElevatedCoverage `
        -Quiet:$SkipBanner
} catch {
    Write-MachineHealthLog "banner_render_failed $($_.Exception.Message)"
}

# User-load heuristic: last input <60s. LASTINPUTINFO is user32 interop --
# if unavailable, default to "not loaded."
function Test-UserLoad {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'UserLoadInterop').Type) {
            Add-Type -Namespace MH -Name UserLoadInterop -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
[DllImport("kernel32.dll")] public static extern uint GetTickCount();
'@
        }
        $lii = New-Object MH.UserLoadInterop+LASTINPUTINFO
        $lii.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lii)
        if ([MH.UserLoadInterop]::GetLastInputInfo([ref]$lii)) {
            $idleMs = [MH.UserLoadInterop]::GetTickCount() - $lii.dwTime
            return ($idleMs -lt 60000)
        }
    } catch {
        Write-Verbose "Test-UserLoad: user32 interop failed. $($_.Exception.Message)"
    }
    return $false
}

$userLoaded = Test-UserLoad
if ($userLoaded -and -not $Force.IsPresent) {
    Write-MachineHealthLog 'user_load_detected deferring_remediations'
} elseif ($userLoaded -and $Force.IsPresent) {
    Write-MachineHealthLog 'user_load_detected force_override_engaged'
    $userLoaded = $false
}

# Load catalog: JSONC parse (comment-aware) + per-entry schema validation.
# Invalid entries are skipped with a warning so a single typo does not block
# the orchestrator from running the rest of the catalog.
$catalogPath = Join-Path $skillRoot 'catalog\checks.jsonc'
$catalog = $null
try {
    $raw = Get-Content -LiteralPath $catalogPath -Raw -ErrorAction Stop
    $catalog = ConvertFrom-Jsonc -InputText $raw
    if ($null -eq $catalog -or -not $catalog.PSObject.Properties['checks']) {
        throw "Catalog missing 'checks' array."
    }
    Write-MachineHealthLog "catalog_loaded entries=$(@($catalog.checks).Count)"
} catch {
    Write-MachineHealthLog "catalog_load_failed $($_.Exception.Message)"
    $catalog = [pscustomobject]@{ checks = @() }
}

# Machine-local catalog overlay: disable/deprecate/demote shipped checks or
# register custom ones without editing the plugin install (a plugin update
# would overwrite it). See references/shared/catalog-overlay.md.
$overlayPath = Join-Path $StateBase 'catalog\checks.local.jsonc'
if (Test-Path -LiteralPath $overlayPath) {
    try {
        $overlayRaw = Get-Content -LiteralPath $overlayPath -Raw -ErrorAction Stop
        $overlay = ConvertFrom-Jsonc -InputText $overlayRaw
        $mergedChecks = @(Merge-CatalogOverlay -BaseChecks @($catalog.checks) -Overlay $overlay)
        $catalog = [pscustomobject]@{ checks = $mergedChecks }
        Write-MachineHealthLog "catalog_overlay_merged path=$overlayPath entries=$($mergedChecks.Count)"
    } catch {
        Write-MachineHealthLog "catalog_overlay_failed $($_.Exception.Message)"
    }
}

$validatedChecks = [System.Collections.Generic.List[object]]::new()
foreach ($entry in @($catalog.checks)) {
    try {
        [void](Assert-CatalogEntry $entry -Because $catalogPath)
        $validatedChecks.Add($entry)
    } catch {
        Write-MachineHealthLog "catalog_entry_invalid skip $($_.Exception.Message)"
    }
}

$windowsChecks = @($validatedChecks | Where-Object {
        ($_.os -contains 'windows') -and ($_.enabled) -and (-not $_.deprecated)
    })

# Load history tail for trend context. Wrap in @() so a first run (no history
# file -> the helper emits nothing, which would bind as $null) yields an empty
# array, which the [AllowEmptyCollection()] consumers below accept.
$historyPath = Join-Path $stateDir 'history.jsonl'
$historyTail = @(Read-HistoryJsonl -Path $historyPath -Tail 8)

# Cadence-aware selection: a weekly run defers monthly-cadence checks that ran
# within the monthly interval (per-check last run from history.jsonl checks_ran).
# on-demand / first-run run everything.
$selection = Get-CheckSelection -Checks $windowsChecks -RunMode $RunMode -HistoryTail $historyTail -Now $runStart
foreach ($sk in @($selection.skipped)) {
    Write-MachineHealthLog ("check_skipped id=$($sk.id) reason=cadence cadence=$($sk.cadence) " +
        "last_run=$($sk.last_run) elapsed_days=$($sk.elapsed_days)")
}
$windowsChecks = @($selection.due)

# Dispatch checks with 90s timeout per check
function Invoke-CheckWithTimeout {
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = 'Parameter passed via -ArgumentList is bound via param block.')]
    param(
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [int] $TimeoutSec = 90,
        [hashtable] $Arguments = @{}
    )
    $jobSw = [System.Diagnostics.Stopwatch]::StartNew()
    # Splat per-check arguments across the job boundary. -ArgumentList serializes
    # the hashtable; @ArgMap binds it to the check's named params. An empty map
    # (the common case) runs the check argument-less.
    $job = Start-Job -ScriptBlock {
        param($ScriptToRun, $ArgMap) & $ScriptToRun @ArgMap
    } -ArgumentList $ScriptPath, $Arguments
    $completed = Wait-Job -Job $job -Timeout $TimeoutSec
    $jobSw.Stop()
    if (-not $completed) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        return @{ ok = $false; reason = 'timeout'; elapsed_ms = [int]$jobSw.ElapsedMilliseconds }
    }
    $outputLines = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
    $joined = ($outputLines | Where-Object { $_ }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($joined)) {
        return @{ ok = $false; reason = 'no_output'; elapsed_ms = [int]$jobSw.ElapsedMilliseconds }
    }
    try {
        $parsed = $joined | ConvertFrom-Json -ErrorAction Stop
        return @{ ok = $true; result = $parsed; elapsed_ms = [int]$jobSw.ElapsedMilliseconds }
    } catch {
        return @{
            ok         = $false
            reason     = 'invalid_json'
            raw_output = $joined
            error      = $_.Exception.Message
            elapsed_ms = [int]$jobSw.ElapsedMilliseconds
        }
    }
}

function New-UnknownCheckResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [string] $Summary,
        [Parameter(Mandatory)] [string] $ErrorReason,
        [int] $DurationMs = 0
    )
    return [pscustomobject]@{
        id               = $Entry.id
        category         = $Entry.category
        os               = 'windows'
        ran_at           = (Get-Date).ToString('o')
        severity         = 'UNKNOWN'
        summary          = $Summary
        detail           = @{}
        commands         = @()
        needs_admin      = [bool]$Entry.needs_admin
        ran_successfully = $false
        duration_ms      = $DurationMs
        trend            = $null
        notes            = $null
        error            = $ErrorReason
    }
}

# Per-run battery report path -- a run-scoped file the battery check writes and
# reads for wear/capacity analysis. runStamp keeps same-day reruns distinct.
$batteryReportPath = Join-Path $logsDir "battery-report-$runStamp.html"

# Ids of checks actually dispatched this run (not cadence-skipped, not
# script-missing). Recorded to history.jsonl checks_ran as the per-check
# last-run signal cadence selection and trend annotation read.
$ranCheckIds = [System.Collections.Generic.List[string]]::new()

$checkResults = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $windowsChecks) {
    $scriptPath = Join-Path $skillRoot $entry.script
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        # Overlay-registered custom checks keep the same scripts/<os>/checks/
        # shape but live under the state base (references/shared/catalog-overlay.md).
        $stateScriptPath = Join-Path $StateBase $entry.script
        if (Test-Path -LiteralPath $stateScriptPath) { $scriptPath = $stateScriptPath }
    }
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        $checkResults.Add((New-UnknownCheckResult -Entry $entry `
                    -Summary "Script not found: $($entry.script)" `
                    -ErrorReason 'script_missing'))
        Write-MachineHealthLog "check_skipped id=$($entry.id) reason=script_missing path=$scriptPath"
        continue
    }

    $ranCheckIds.Add($entry.id)
    $checkArgs = Get-CheckArgument -CheckId $entry.id -RunLog $runLog -BatteryReportPath $batteryReportPath
    Write-MachineHealthLog "check_dispatch id=$($entry.id) script=$($entry.script)"
    $dispatch = Invoke-CheckWithTimeout -ScriptPath $scriptPath -TimeoutSec 90 -Arguments $checkArgs

    if (-not $dispatch.ok) {
        $checkResults.Add((New-UnknownCheckResult -Entry $entry `
                    -Summary "Check did not produce a valid result ($($dispatch.reason))." `
                    -ErrorReason $dispatch.reason `
                    -DurationMs ([int]$dispatch.elapsed_ms)))
        Write-MachineHealthLog ("check_failed id=$($entry.id) reason=$($dispatch.reason) " +
            "elapsed_ms=$($dispatch.elapsed_ms)")
    } else {
        $checkResults.Add($dispatch.result)
        Write-MachineHealthLog ("check_ok id=$($entry.id) severity=$($dispatch.result.severity) " +
            "elapsed_ms=$($dispatch.elapsed_ms)")
    }
}

# Trend-aware severity adjustment + annotation per severity-rubric.md.
try {
    $checkResults = @(Invoke-TrendAnalysis -CheckResults $checkResults -HistoryTail $historyTail)
} catch {
    Write-MachineHealthLog "trend_analysis_failed $($_.Exception.Message)"
}

# Cross-finding correlation: pair related findings + upgrade severity per
# references/shared/correlation-rules.md. Additive; never downgrades.
try {
    $checkResults = @(Invoke-FindingCorrelation -CheckResults $checkResults)
} catch {
    Write-MachineHealthLog "correlation_failed $($_.Exception.Message)"
}

# Remediation dispatch (dry-run-aware, user-load-aware, approval-gated via approvals.json)
$remediationAttempts = [System.Collections.Generic.List[object]]::new()
$remediationsEnabled = (-not $effectiveDry) -and (-not $userLoaded)

$todoPath = Join-Path $skillRoot 'TODO.md'
$approvalState = Get-ApprovalState -StateDir $stateDir -TodoPath $todoPath -LogPath $runLog

function Invoke-Remediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Script,
        [Parameter(Mandatory = $false)] [string] $FindingJson
    )

    $scriptPath = Join-Path $PSScriptRoot $Script
    if (-not (Test-Path -LiteralPath $scriptPath)) { return $null }
    try {
        # Remediations that take -Finding accept the JSON via that parameter;
        # remediations that don't need findings run with no arguments.
        $out = if ($FindingJson) {
            & $scriptPath -Finding $FindingJson
        } else {
            & $scriptPath
        }
        $joined = ($out | Where-Object { $_ }) -join "`n"
        return $joined | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-MachineHealthLog "remediation_error script=$Script $($_.Exception.Message)"
        return $null
    }
}

if ($remediationsEnabled) {
    $servicesFinding = $checkResults | Where-Object id -EQ 'services' | Select-Object -First 1
    $restartApproved = Test-ApprovalGranted -State $approvalState -RemediationId 'restart-stopped-service'
    if ($servicesFinding -and $servicesFinding.severity -eq 'WARN' -and $restartApproved) {
        $findingJson = $servicesFinding | ConvertTo-Json -Depth 10 -Compress
        $out = Invoke-Remediation -Script 'remediations\Restart-StoppedService.ps1' -FindingJson $findingJson
        if ($out) {
            foreach ($att in @($out)) {
                $remediationAttempts.Add($att)
                Add-Content -LiteralPath $remedLog -Value ($att | ConvertTo-Json -Depth 10 -Compress) -Encoding utf8
            }
        }
    }

    $diskFinding = $checkResults | Where-Object id -EQ 'disk-space' | Select-Object -First 1
    $clearApproved = Test-ApprovalGranted -State $approvalState -RemediationId 'clear-temp-files'
    if ($diskFinding -and $diskFinding.severity -in @('WARN', 'CRIT') -and $clearApproved) {
        $out = Invoke-Remediation -Script 'remediations\Clear-TempFiles.ps1'
        if ($out) {
            $remediationAttempts.Add($out)
            Add-Content -LiteralPath $remedLog `
                -Value ($out | ConvertTo-Json -Depth 10 -Compress) -Encoding utf8
        }
    }
} else {
    $reason = if ($effectiveDry) { 'dry_run' } elseif ($userLoaded) { 'user_load' } else { 'disabled' }
    Write-MachineHealthLog "remediations_skipped reason=$reason"
}

# Discovery: inventory host dimensions vs catalog; propose up to 3 new checks.
$discoveredChecks = @()
try {
    $probes = @(Get-WindowsDiscoveryProbe)
    $discoveredChecks = @(Invoke-Discovery -Catalog $validatedChecks -ProbeResults $probes -MaxProposals 3)
} catch {
    Write-MachineHealthLog "discovery_failed $($_.Exception.Message)"
}

# First-run proposal: suggest installing Microsoft.WinGet.Client module when
# it's absent. The text-parse fallback is localization-fragile. Never auto-
# install per SKILL.md. Proposals are machine-specific state -- write to the
# per-run logs directory (user-owned), print a loud banner to stderr, and
# append a log line. Never write to the repo.
if ($RunMode -eq 'first-run') {
    try {
        $hasWingetModule = $null -ne (Get-Module -ListAvailable Microsoft.WinGet.Client -ErrorAction SilentlyContinue)
        if (-not $hasWingetModule) {
            $proposalPath = Join-Path $logsDir 'first-run-proposals.md'
            $proposal = @'

### First-run proposal: install Microsoft.WinGet.Client module

The winget-upgrades check prefers the official Microsoft.WinGet.Client
PowerShell module (v1.12+) for authoritative, localization-safe upgrade
data. The text-parse fallback is fragile on non-English Windows. To
upgrade coverage:

    Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force

This is a proposal only. Per SKILL.md, the skill never auto-installs
modules. Harmless to ignore.

'@
            Add-Content -LiteralPath $proposalPath -Value $proposal -Encoding utf8
            Write-StderrBanner -Line @(
                '[machine-health] First-run proposal: install Microsoft.WinGet.Client'
                '[machine-health] for authoritative winget data.'
                "[machine-health] See: $proposalPath"
            )
            Write-MachineHealthLog "first_run_proposed_winget_client_module proposal_path=$proposalPath"
        }
    } catch {
        Write-MachineHealthLog "first_run_proposal_failed $($_.Exception.Message)"
    }
}

# Severity counts by category
$severityCounts = @{}
foreach ($r in $checkResults) {
    $cat = $r.category
    if (-not $severityCounts.ContainsKey($cat)) {
        $severityCounts[$cat] = @{ OK = 0; INFO = 0; WARN = 0; CRIT = 0; UNKNOWN = 0 }
    }
    $severityCounts[$cat][$r.severity]++
}

$succeededCount = @($remediationAttempts | Where-Object succeeded).Count
$remediationCounts = @{
    attempted = $remediationAttempts.Count
    succeeded = $succeededCount
    failed    = $remediationAttempts.Count - $succeededCount
}

$runEnd = Get-Date
$durationSeconds = [math]::Round(($runEnd - $runStart).TotalSeconds, 1)

# Run snapshot
$osVersion = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Version } catch { 'unknown' }

$urlsCalled = @()
try {
    # Scope to current run only -- the log file is day-scoped (run-YYYY-MM-DD.log)
    # so a second run on the same day would otherwise inherit earlier runs'
    # URLs. Compare as DateTimeOffset so mixed offsets (e.g., DST fall-back)
    # order chronologically, not lexicographically. Lines whose timestamp
    # fails to parse are dropped with a log note rather than included.
    $runStartOffset = [DateTimeOffset]::Parse($runId)
    $urlsCalled = @(Read-EgressLog -LogPath $runLog |
            Where-Object {
                $parsed = [DateTimeOffset]::MinValue
                if ([DateTimeOffset]::TryParse($_.timestamp, [ref]$parsed)) {
                    $parsed -ge $runStartOffset
                } else {
                    Write-MachineHealthLog "urls_called_unparsable_timestamp $($_.timestamp)"
                    $false
                }
            } |
            ForEach-Object { $_.uri } |
            Sort-Object -Unique)
} catch {
    Write-MachineHealthLog "urls_called_parse_failed $($_.Exception.Message)"
}

$snapshot = [ordered]@{
    run_id             = $runId
    hostname           = $hostname
    os                 = 'windows'
    os_version         = $osVersion
    elevated           = $elevated
    run_mode           = $RunMode
    dry_run            = $effectiveDry
    powershell_version = $PSVersionTable.PSVersion.ToString()
    checks             = @($checkResults)
    remediations       = @($remediationAttempts)
    discovered_checks  = @($discoveredChecks)
    urls_called        = @($urlsCalled)
    duration_seconds   = $durationSeconds
}

$latestPath = Join-Path $stateDir 'latest.json'
$snapshot | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $latestPath -Encoding utf8 -Force
Write-MachineHealthLog "wrote_latest_json path=$latestPath"

# Compact history line -- extract scalar detail properties per check into
# top_metrics so subsequent runs can detect trend context. Keys use the
# "{checkId}.{detailKey}" convention documented in references/shared/output-schema.md.
$topMetrics = ConvertTo-TopMetric -CheckResults $checkResults

$historyLine = [ordered]@{
    run_id             = $runId
    hostname           = $hostname
    os                 = 'windows'
    elevated           = $elevated
    severity_counts    = $severityCounts
    remediation_counts = $remediationCounts
    duration_seconds   = $durationSeconds
    checks_ran         = @($ranCheckIds)
    top_metrics        = $topMetrics
}
$historyJson = $historyLine | ConvertTo-Json -Depth 10 -Compress
Add-Content -LiteralPath $historyPath -Value $historyJson -Encoding utf8
Write-MachineHealthLog "appended_history path=$historyPath"

# Report render (minimal but template-driven)
$templatePath = Join-Path $skillRoot 'references\shared\report-template.md'
# Per-run (not per-day) filename: a same-day rerun must not overwrite the
# earlier report, since each run also writes a distinct history entry.
$reportPath = Join-Path $reportsDir "health-$runStamp.md"

$totalBySeverity = @{ OK = 0; INFO = 0; WARN = 0; CRIT = 0; UNKNOWN = 0 }
foreach ($r in $checkResults) { $totalBySeverity[$r.severity]++ }

$oneLine = ("$($totalBySeverity.CRIT) CRIT, $($totalBySeverity.WARN) WARN, " +
    "$($totalBySeverity.INFO) INFO, $($totalBySeverity.OK) OK, " +
    "$($totalBySeverity.UNKNOWN) UNKNOWN")

function Format-Finding {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] $Result)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("#### $($Result.id) - $($Result.summary)")
    $lines.Add('')
    $lines.Add("**Severity:** $($Result.severity)")
    $lines.Add('')
    if ($Result.notes) {
        $lines.Add("_Note: $($Result.notes)_")
        $lines.Add('')
    }
    if ($Result.commands -and $Result.commands.Count -gt 0) {
        $lines.Add('**Reproduce:**')
        $lines.Add('')
        $lines.Add('```powershell')
        foreach ($c in $Result.commands) { $lines.Add($c) }
        $lines.Add('```')
        $lines.Add('')
    }
    return ($lines -join "`n")
}

function Format-Section {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Severity)

    $items = @($checkResults | Where-Object { $_.severity -eq $Severity })
    if ($items.Count -eq 0) { return '_No findings at this severity._' }
    return (($items | ForEach-Object { Format-Finding -Result $_ }) -join "`n`n")
}

$okList = @($checkResults |
        Where-Object { $_.severity -eq 'OK' } |
        ForEach-Object { "- **$($_.id)** - $($_.summary)" }) -join "`n"
if (-not $okList) { $okList = '_none_' }

$glanceRows = @($checkResults | ForEach-Object {
        "| $($_.category) | $($_.id) | **$($_.severity)** | $($_.summary) | - |"
    }) -join "`n"
$glanceTable = @"
| Category | Check | Severity | Summary | Trend |
|---|---|---|---|---|
$glanceRows
"@

$remediationsSection = if ($remediationAttempts.Count -eq 0) {
    if (-not $remediationsEnabled) {
        $reason = if ($effectiveDry) {
            'dry-run mode'
        } elseif ($userLoaded) {
            'user load detected'
        } else {
            'no approvals in approvals.json'
        }
        "_No remediations attempted ($reason)._"
    } else {
        '_No remediation conditions met this run._'
    }
} else {
    ($remediationAttempts | ForEach-Object {
        $mark = if ($_.succeeded) { 'OK' } else { 'FAIL' }
        "- **$mark** $($_.id) - $($_.target)"
    }) -join "`n"
}

$discoverySection = Get-DiscoveryMarkdown -Proposals $discoveredChecks
$openQuestions = '_No new TODO entries this run._'

$appendixSection = try {
    ConvertTo-AppendixMarkdown -CheckResults $checkResults
} catch {
    Write-MachineHealthLog "appendix_render_failed $($_.Exception.Message)"
    '_Appendix render failed; see run log._'
}

$deltaLine = try {
    Get-RunDelta -HistoryTail $historyTail -CurrentSeverityCounts $severityCounts `
        -SkippedCount @($selection.skipped).Count
} catch {
    Write-MachineHealthLog "delta_compute_failed $($_.Exception.Message)"
    'see state/history.jsonl for comparison'
}

function Get-ReportTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $TemplatePath)

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        return "# Machine health -- {{hostname}}`n`n{{severity_counts_oneline}}"
    }

    $raw = Get-Content -LiteralPath $TemplatePath -Raw

    # The report-template.md file is a spec document that embeds the actual
    # template inside a fenced markdown code block (```markdown ... ```).
    # Extract that block so the spec doesn't bleed into the rendered report.
    $pattern = '(?ms)^```markdown\s*\r?\n(.*?)\r?\n```\s*$'
    $match = [regex]::Match($raw, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    # Fallback: if no fenced block, assume the entire file is the template.
    # The previous anchor-based fallback (find "\n# Machine health") was
    # fragile -- a heading variant or leading whitespace would break it.
    return $raw
}

$template = Get-ReportTemplate -TemplatePath $templatePath

$report = $template
$durationHuman = if ($durationSeconds -lt 60) {
    "$([int]$durationSeconds)s"
} else {
    "$([int]($durationSeconds / 60))m $([int]($durationSeconds % 60))s"
}

$elevationCoverage = try {
    Get-ElevationCoverageMarkdown -Elevated $elevated -Matrix (Get-ElevationMatrix)
} catch {
    Write-MachineHealthLog "elevation_coverage_failed $($_.Exception.Message)"
    '_Elevation coverage not rendered._'
}

$adminGatedCount = $elevated ? 0 : @(Get-ElevationMatrix).Count
$elevatedLabel = if ($elevated) {
    'yes'
} elseif ($adminGatedCount -gt 0) {
    "no - $adminGatedCount admin-gated capabilities skipped"
} else {
    'no'
}

$replacements = @{
    '{{hostname}}'                 = $hostname
    '{{os}}'                       = 'windows'
    '{{os_version}}'               = $osVersion
    '{{run_id}}'                   = $runId
    '{{run_id_date}}'              = $runDate
    '{{run_duration_seconds}}'     = $durationHuman
    '{{elevated}}'                 = $elevatedLabel
    '{{elevation_coverage}}'       = $elevationCoverage
    '{{severity_counts_oneline}}'  = $oneLine
    '{{delta_vs_prior_oneline}}'   = $deltaLine
    '{{at_a_glance_table}}'        = $glanceTable
    '{{crit_findings}}'            = Format-Section 'CRIT'
    '{{warn_findings}}'            = Format-Section 'WARN'
    '{{info_findings}}'            = Format-Section 'INFO'
    '{{unknown_checks}}'           = Format-Section 'UNKNOWN'
    '{{ok_count}}'                 = [string]$totalBySeverity.OK
    '{{ok_checks_collapsed}}'      = $okList
    '{{remediations_section}}'     = $remediationsSection
    '{{discovery_section}}'        = $discoverySection
    '{{open_questions}}'           = $openQuestions
    '{{appendix}}'                 = $appendixSection
}
foreach ($k in $replacements.Keys) {
    $report = $report.Replace($k, [string]$replacements[$k])
}

$report | Out-File -LiteralPath $reportPath -Encoding utf8 -Force
Write-MachineHealthLog "wrote_report path=$reportPath"
Write-MachineHealthLog "run_end run_id=$runId duration_seconds=$durationSeconds"

if ($Human) {
    Write-Output "machine-health report: $reportPath"
    Write-Output "  severity: $oneLine"
    Write-Output "  duration: $durationHuman"
    Write-Output "  snapshot: $latestPath"
} else {
    $snapshot | ConvertTo-Json -Depth 20
}
