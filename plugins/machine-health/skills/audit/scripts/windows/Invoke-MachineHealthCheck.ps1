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
 8. Render a markdown report from reference/shared/report-template.md.
 9. Return the full run snapshot as JSON on stdout (unless -Human is set).

.PARAMETER OutputBase
Root folder for reports/. Created on first run.

.PARAMETER StateBase
Root folder for state/ and logs/ (history, approvals, run logs). Resolution:
explicit parameter, then the CLAUDE_PLUGIN_DATA environment variable (the
per-plugin data directory that survives plugin updates), then OutputBase.

When a OneDrive variable names StateBase or one of its ancestors, the run still
dispatches the checks and writes the markdown report, adds one UNKNOWN
state-location result, and creates or writes nothing else under StateBase. The
one exemption: when OutputBase is at or under that StateBase, the report and
its reports/ folder are still written there.

.PARAMETER RunMode
weekly | on-demand | first-run. first-run forces DryRun = $true.

.PARAMETER DryRun
Skip all remediations; still produce a full report.

.PARAMETER Human
Print a human-readable summary instead of emitting the run snapshot JSON.

.PARAMETER SampleSeconds
Sampling window, in seconds, for checks that sample over time (top-processes).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $OutputBase,
    [string] $StateBase,
    [ValidateSet('weekly', 'on-demand', 'first-run')] [string] $RunMode = 'weekly',
    [switch] $DryRun,
    [switch] $Human,
    [switch] $Force,
    [switch] $SkipBanner,
    [ValidateRange(5, 60)] [int] $SampleSeconds = 15
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'

$libRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libRoot 'Resolve-SkillRoot.ps1')
$skillRoot = Resolve-SkillRoot
. (Join-Path $libRoot 'Write-MachineHealthLog.ps1')
. (Join-Path $libRoot 'Test-IsElevated.ps1')
. (Join-Path $libRoot 'Read-HistoryJsonl.ps1')
. (Join-Path $libRoot 'ConvertFrom-Jsonc.ps1')
. (Join-Path $libRoot 'Assert-CatalogEntry.ps1')
. (Join-Path $libRoot 'New-InvalidCatalogEntryResult.ps1')
. (Join-Path $libRoot 'Get-ApprovalState.ps1')
. (Join-Path $libRoot 'Add-TodoProposal.ps1')
. (Join-Path $libRoot 'Invoke-AllowlistedWeb.ps1')
. (Join-Path $libRoot 'Get-ElevationMatrix.ps1')
. (Join-Path $libRoot 'Write-ElevationBanner.ps1')
. (Join-Path $libRoot 'Format-CheckLabel.ps1')
. (Join-Path $libRoot 'Get-NonElevatedCoverage.ps1')
. (Join-Path $libRoot 'ConvertTo-TopMetrics.ps1')
. (Join-Path $libRoot 'Invoke-TrendAnalysis.ps1')
. (Join-Path $libRoot 'Get-RunDelta.ps1')
. (Join-Path $libRoot 'Invoke-Discovery.ps1')
. (Join-Path $libRoot 'Get-WindowsDiscoveryProbes.ps1')
. (Join-Path $libRoot 'ConvertTo-AppendixMarkdown.ps1')
. (Join-Path $libRoot 'ConvertTo-DetailMarkdown.ps1')
. (Join-Path $libRoot 'Invoke-FindingCorrelation.ps1')
. (Join-Path $libRoot 'Invoke-CustomCheckClamp.ps1')
. (Join-Path $libRoot 'Merge-CatalogOverlay.ps1')
. (Join-Path $libRoot 'Get-CheckSelection.ps1')
. (Join-Path $libRoot 'Get-CheckArgument.ps1')
. (Join-Path $libRoot 'Get-MutedFindingKey.ps1')
. (Join-Path $libRoot 'Invoke-CheckWithTimeout.ps1')
. (Join-Path $libRoot 'Enter-RunLock.ps1')
. (Join-Path $libRoot 'Assert-StateBaseLocation.ps1')
. (Join-Path $libRoot 'New-RunSnapshot.ps1')

# stderr keeps stdout clean for the JSON snapshot.
function Write-StderrBanner {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string[]] $Line)

    [Console]::Error.WriteLine('')
    foreach ($l in $Line) { [Console]::Error.WriteLine($l) }
    [Console]::Error.WriteLine('')
}

function New-UnknownCheckResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory result object; changes no system state.')]
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

$runStart = Get-Date
$runId = $runStart.ToString('o')
$runDate = $runStart.ToString('yyyy-MM-dd')
# Filesystem-safe UTC run stamp for per-run artifact names (colons are invalid
# in Windows paths). Millisecond precision so two runs in the same second (a
# scheduler retry/overlap, or a fast mostly-cadence-deferred run) still write
# distinct report/battery filenames rather than overwriting each other.
$runStamp = $runStart.ToUniversalTime().ToString('yyyy-MM-ddTHHmmssfffZ')
$hostname = [System.Net.Dns]::GetHostName()
$effectiveDry = $DryRun.IsPresent -or ($RunMode -eq 'first-run')
$elevated = Test-IsElevated
$osVersion = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Version } catch { 'unknown' }

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

# Plugin state never goes into a cloud-synced folder; see the StateBase
# parameter help for what a synced StateBase still gets.
$guardWarnings = @()
$stateLocation = Assert-StateBaseLocation -Path $StateBase -WarningVariable +guardWarnings -WarningAction SilentlyContinue
$outputLocation = Assert-StateBaseLocation -Path $OutputBase -WarningVariable +guardWarnings -WarningAction SilentlyContinue
$stateWritable = -not $stateLocation.Synced
foreach ($w in $guardWarnings) { [Console]::Error.WriteLine("[machine-health] WARNING: $w") }
if (-not $stateWritable) {
    Write-StderrBanner -Line ("[machine-health] WARNING: the state folder '$StateBase' is under a cloud sync root " +
        "($($stateLocation.Rule): '$($stateLocation.Folder)'). Running the checks and the report only; " +
        'nothing is written under it. Move the plugin data folder out of the synced folder.')
}
if ($outputLocation.Synced) {
    Write-StderrBanner -Line ("[machine-health] WARNING: the report folder '$OutputBase' is under a cloud sync root " +
        "($($outputLocation.Rule): '$($outputLocation.Folder)'); reports will sync.")
}

function Initialize-Directory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string[]] $Path)

    foreach ($d in $Path) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

if ($stateWritable) { Initialize-Directory -Path @($StateBase, $stateDir) }

# One run at a time per state folder: a second run reports the held lock and
# writes nothing. The short wait covers a run that is just releasing it.
$runLock = $null
if ($stateWritable) {
    $runLock = Enter-RunLock -StateDir $stateDir -Name 'run' -TimeoutSeconds 2
    if ($null -eq $runLock) {
        $lockPath = Join-Path $stateDir 'run.lock'
        $lockResult = New-UnknownCheckResult -Entry ([pscustomobject]@{ id = 'run-lock'; category = 'config'; needs_admin = $false }) `
            -Summary "Another machine-health run holds '$lockPath'; this run did nothing." -ErrorReason 'run_locked'
        [Console]::Error.WriteLine("[machine-health] $($lockResult.summary)")
        if ($Human) {
            Write-Output "machine-health: UNKNOWN run-lock - $($lockResult.summary)"
        } else {
            New-RunSnapshot -RunId $runId -HostName $hostname -OsVersion $osVersion -Elevated $elevated `
                -RunMode $RunMode -DryRun $effectiveDry -Checks @($lockResult) | ConvertTo-Json -Depth 20
        }
        exit 0
    }
}

# The log defaults bound below live in the caller's $PSDefaultParameterValues; the finally
# puts back whatever was there so a later run in the same session starts clean.
$logDefaultKeys = @('Write-MachineHealthLog:LogPath', 'Write-MachineHealthLog:ToStderr')
$savedLogDefaults = @{}
foreach ($k in $logDefaultKeys) {
    if ($PSDefaultParameterValues.ContainsKey($k)) { $savedLogDefaults[$k] = $PSDefaultParameterValues[$k] }
}

# Everything below runs while run.lock is held; the finally releases it on every exit path.
try {
    Initialize-Directory -Path @($OutputBase, $reportsDir)
    if ($stateWritable) { Initialize-Directory -Path $logsDir }

    if ($stateWritable) {
        $runLog = Join-Path $logsDir "run-$runDate.log"
        $remedLog = Join-Path $logsDir "remediation-$runDate.log"
        # Bind LogPath once for the 30+ orchestrator-local Write-MachineHealthLog calls below.
        $PSDefaultParameterValues['Write-MachineHealthLog:LogPath'] = $runLog
    } else {
        $runLog = $null
        $remedLog = $null
        # Nothing is written under a synced StateBase, so run log lines go to stderr.
        $PSDefaultParameterValues['Write-MachineHealthLog:ToStderr'] = $true
    }

    Write-MachineHealthLog ("run_start run_id=$runId mode=$RunMode dry_run=$($DryRun.IsPresent) " +
        "output_base=$OutputBase state_base=$StateBase state_writable=$stateWritable")

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

    if ($effectiveDry -and -not $DryRun.IsPresent) {
        Write-MachineHealthLog 'dry_run forced by RunMode=first-run'
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
    # Invalid entries are skipped for dispatch so a single typo does not block the
    # rest of the catalog, but each skip is synthesized as an UNKNOWN CheckResult
    # so the report / latest.json / severity_counts surface it (not only the run log).
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
    $shippedIds = @($catalog.checks | Where-Object { $_ -and $_.PSObject.Properties['id'] } | ForEach-Object { [string]$_.id })
    $customIds = @()

    # Machine-local catalog overlay: disable/deprecate/demote shipped checks or
    # register custom ones without editing the plugin install (a plugin update
    # would overwrite it). See reference/shared/catalog-overlay.md.
    $overlayPath = Join-Path $StateBase 'catalog\checks.local.jsonc'
    if (Test-Path -LiteralPath $overlayPath) {
        try {
            $overlayRaw = Get-Content -LiteralPath $overlayPath -Raw -ErrorAction Stop
            $overlay = ConvertFrom-Jsonc -InputText $overlayRaw
            $mergedChecks = @(Merge-CatalogOverlay -BaseChecks @($catalog.checks) -Overlay $overlay)
            $catalog = [pscustomobject]@{ checks = $mergedChecks }
            $customIds = @($mergedChecks |
                    Where-Object { $_ -and $_.PSObject.Properties['id'] -and $shippedIds -notcontains [string]$_.id } |
                    ForEach-Object { [string]$_.id })
            Write-MachineHealthLog "catalog_overlay_merged path=$overlayPath entries=$($mergedChecks.Count) custom=$($customIds.Count)"
        } catch {
            Write-MachineHealthLog "catalog_overlay_failed $($_.Exception.Message)"
        }
    }

    $validatedChecks = [System.Collections.Generic.List[object]]::new()
    $invalidCatalogResults = [System.Collections.Generic.List[object]]::new()
    # Seed occupied ids so synthetic fallbacks never collide with a real catalog id
    # (e.g. invalid DiskSpace at index 2 vs a custom check named invalid-catalog-entry-2).
    $occupiedResultIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($seedEntry in @($catalog.checks)) {
        if ($null -eq $seedEntry -or -not $seedEntry.PSObject.Properties['id']) { continue }
        $seedId = [string]$seedEntry.id
        if ($seedId -cmatch '^[a-z][a-z0-9-]*[a-z0-9]$') {
            [void]$occupiedResultIds.Add($seedId)
        }
    }
    $entryIndex = 0
    foreach ($entry in @($catalog.checks)) {
        try {
            [void](Assert-CatalogEntry $entry -Because $catalogPath)
            $validatedChecks.Add($entry)
        } catch {
            Write-MachineHealthLog "catalog_entry_invalid skip $($_.Exception.Message)"
            $invalidResult = New-InvalidCatalogEntryResult `
                -Entry $entry `
                -Index $entryIndex `
                -ErrorMessage $_.Exception.Message `
                -OccupiedIds @($occupiedResultIds)
            $invalidCatalogResults.Add($invalidResult)
            [void]$occupiedResultIds.Add([string]$invalidResult.id)
        }
        $entryIndex++
    }

    $windowsChecks = @($validatedChecks | Where-Object {
            ($_.os -contains 'windows') -and ($_.enabled) -and (-not $_.deprecated)
        })

    # Pre-run elevation banner (stderr only; stdout remains clean JSON).
    # Non-elevated + no -SkipBanner => print the coverage matrix so the user
    # knows up-front what will be degraded and how to re-run with admin. The
    # covered list comes from the loaded catalog, so it runs after the load; a
    # failed load leaves it empty and the banner omits that section.
    try {
        Write-ElevationBanner `
            -Elevated $elevated `
            -HostName $hostname `
            -UserName ("$env:USERDOMAIN\$env:USERNAME") `
            -OutputBase $OutputBase `
            -StateBase $StateBase `
            -SkillRoot $skillRoot `
            -Matrix @(Get-ElevationMatrix) `
            -NonElevatedCoverage @(Get-NonElevatedCoverage -Catalog $windowsChecks -CustomIds $customIds) `
            -Quiet:$SkipBanner
    } catch {
        Write-MachineHealthLog "banner_render_failed $($_.Exception.Message)"
    }

    # Load history tail. Depth 100 (not 8) so cadence selection can still find a
    # monthly check's last run when many weekly reruns / on-demand runs fall inside
    # the ~27-day interval -- an 8-line tail would push the last actual run off the
    # window and re-run the check prematurely. Trend uses only the recent slice.
    # Wrap in @() so a first run (no history file -> the helper emits nothing, which
    # would bind as $null) yields an empty array for the [AllowEmptyCollection()]
    # consumers below.
    $historyDepth = 100
    $historyPath = Join-Path $stateDir 'history.jsonl'
    $historyTail = @(Read-HistoryJsonl -Path $historyPath -Tail $historyDepth)
    $historyRecent = @($historyTail | Select-Object -Last 8)

    # Cadence-aware selection: a weekly run defers monthly-cadence checks that ran
    # within the monthly interval (per-check last run from history.jsonl checks_ran).
    # on-demand / first-run run everything.
    $selection = Get-CheckSelection -Checks $windowsChecks -RunMode $RunMode -HistoryTail $historyTail -Now $runStart
    foreach ($sk in @($selection.skipped)) {
        Write-MachineHealthLog ("check_skipped id=$($sk.id) reason=cadence cadence=$($sk.cadence) " +
            "last_run=$($sk.last_run) elapsed_days=$($sk.elapsed_days)")
    }
    $windowsChecks = @($selection.due)

    # Per-run battery report path -- a run-scoped file the battery check writes and
    # reads for wear/capacity analysis. runStamp keeps same-day reruns distinct.
    $batteryReportPath = if ($stateWritable) { Join-Path $logsDir "battery-report-$runStamp.html" } else { $null }

    # Ids of checks that produced a usable result this run (not cadence-skipped,
    # not script-missing, not a failed dispatch). Recorded to history.jsonl
    # checks_ran as the per-check last-run signal cadence selection and trend
    # annotation read.
    $ranCheckIds = [System.Collections.Generic.List[string]]::new()

    $checkResults = [System.Collections.Generic.List[object]]::new()
    # Surface Assert-CatalogEntry failures through the normal reporting path first
    # so a registered-but-invalid check cannot silently vanish from the report.
    $checkResults.AddRange($invalidCatalogResults)
    if (-not $stateWritable) {
        $checkResults.Add((New-UnknownCheckResult `
                    -Entry ([pscustomobject]@{ id = 'state-location'; category = 'config'; needs_admin = $false }) `
                    -Summary ("State folder '$StateBase' is under a cloud sync root ($($stateLocation.Rule): " +
                        "'$($stateLocation.Folder)'); no state was written and no remediation ran.") `
                    -ErrorReason 'state_under_sync_root'))
    }
    # Mutes reach checks only as an argument; checks never read mutes.json.
    $muteState = Get-MuteState -StateDir $stateDir
    foreach ($entry in $windowsChecks) {
        $scriptPath = Join-Path $skillRoot $entry.script
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            # Overlay-registered custom checks keep the same scripts/<os>/checks/
            # shape but live under the state base (reference/shared/catalog-overlay.md).
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

        $muted = Get-MutedFindingKey -State $muteState -CheckId $entry.id
        $checkArgs = Get-CheckArgument -CheckId $entry.id -ScriptPath $scriptPath -RunLog $runLog `
            -BatteryReportPath $batteryReportPath -MutedKeys $muted -SampleSeconds $SampleSeconds
        Write-MachineHealthLog "check_dispatch id=$($entry.id) script=$($entry.script)"
        $dispatch = Invoke-CheckWithTimeout -ScriptPath $scriptPath -TimeoutSec (Get-CheckTimeoutSec -Arguments $checkArgs) `
            -Arguments $checkArgs

        if (-not $dispatch.ok) {
            $checkResults.Add((New-UnknownCheckResult -Entry $entry `
                        -Summary "Check did not produce a valid result ($($dispatch.reason))." `
                        -ErrorReason $dispatch.reason `
                        -DurationMs ([int]$dispatch.elapsed_ms)))
            Write-MachineHealthLog ("check_failed id=$($entry.id) reason=$($dispatch.reason) " +
                "elapsed_ms=$($dispatch.elapsed_ms)")
        } else {
            # Record checks_ran ONLY when the check produced a SUCCESSFUL result.
            # A schema-valid but failed result (ran_successfully=false -- e.g. a
            # transient error, or a cmdlet unavailable) is not a real cadence signal:
            # counting it would defer a monthly check ~27 days on a failed run
            # instead of retrying it next run. (Timeout / no-output / invalid-JSON
            # dispatches already miss this branch entirely.)
            if ($dispatch.result.ran_successfully) {
                $ranCheckIds.Add($entry.id)
            }
            $checkResults.Add($dispatch.result)
            Write-MachineHealthLog ("check_ok id=$($entry.id) severity=$($dispatch.result.severity) " +
                "elapsed_ms=$($dispatch.elapsed_ms)")
        }
    }

    # Trend-aware severity adjustment + annotation per severity-rubric.md. Trend
    # reads the recent slice (last ~8 runs); cadence uses the full depth above.
    try {
        $checkResults = @(Invoke-TrendAnalysis -CheckResults $checkResults -HistoryTail $historyRecent)
    } catch {
        Write-MachineHealthLog "trend_analysis_failed $($_.Exception.Message)"
    }

    # Cross-finding correlation: pair related findings + upgrade severity per
    # reference/shared/correlation-rules.md. Additive; never downgrades.
    try {
        $checkResults = @(Invoke-FindingCorrelation -CheckResults $checkResults)
    } catch {
        Write-MachineHealthLog "correlation_failed $($_.Exception.Message)"
    }

    # Custom-check clamp: after every upgrade path, so no rule can lift a custom
    # check past WARN before it has a clean record (reference/shared/catalog-overlay.md).
    try {
        $checkResults = @(Invoke-CustomCheckClamp -CheckResults $checkResults -CustomIds $customIds `
                -HistoryTail $historyTail)
    } catch {
        Write-MachineHealthLog "custom_clamp_failed $($_.Exception.Message)"
    }

    # Remediation dispatch (dry-run-aware, user-load-aware, approval-gated via approvals.json)
    $remediationAttempts = [System.Collections.Generic.List[object]]::new()
    $remediationsEnabled = (-not $effectiveDry) -and (-not $userLoaded) -and $stateWritable

    $todoPath = Get-TodoPath -StateBase $StateBase
    $queuedTodoTitles = [System.Collections.Generic.List[string]]::new()
    # Get-ApprovalState creates the state folder and may run the one-time checkbox migration,
    # so a synced StateBase skips it.
    $approvalState = if ($stateWritable) {
        Get-ApprovalState -StateDir $stateDir -TodoPath $todoPath -LogPath $runLog
    } else {
        New-DefaultApprovalState
    }

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
        $reason = if ($effectiveDry) {
            'dry_run'
        } elseif ($userLoaded) {
            'user_load'
        } elseif (-not $stateWritable) {
            'state_location'
        } else {
            'disabled'
        }
        Write-MachineHealthLog "remediations_skipped reason=$reason"
    }

    $discoveredChecks = @()
    try {
        $probes = @(Get-WindowsDiscoveryProbe)
        $discoveredChecks = @(Invoke-Discovery -Catalog $validatedChecks -ProbeResults $probes -MaxProposals 3)
    } catch {
        Write-MachineHealthLog "discovery_failed $($_.Exception.Message)"
    }

    # First-run proposal: suggest installing Microsoft.WinGet.Client module when
    # it's absent. The text-parse fallback is localization-fragile. Never auto-
    # install per SKILL.md. The proposal is machine-specific state: queue it in the
    # state-root proposals file (Get-TodoPath), print a loud banner to stderr, and
    # append a log line. Never write to the repo.
    if ($RunMode -eq 'first-run' -and $stateWritable) {
        try {
            $hasWingetModule = $null -ne (Get-Module -ListAvailable Microsoft.WinGet.Client -ErrorAction SilentlyContinue)
            if (-not $hasWingetModule) {
                $proposalTitle = 'First-run proposal: install Microsoft.WinGet.Client module'
                $proposal = @'
The winget-upgrades check prefers the official Microsoft.WinGet.Client
PowerShell module (v1.12+) for authoritative, localization-safe upgrade
data. The text-parse fallback is fragile on non-English Windows. To
upgrade coverage:

    Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force

This is a proposal only. Per SKILL.md, the skill never auto-installs
modules. Harmless to ignore.
'@
                if (Add-TodoProposal -TodoPath $todoPath -Title $proposalTitle -Body $proposal) {
                    $queuedTodoTitles.Add($proposalTitle)
                }
                Write-StderrBanner -Line @(
                    '[machine-health] First-run proposal: install Microsoft.WinGet.Client'
                    '[machine-health] for authoritative winget data.'
                    "[machine-health] See: $todoPath"
                )
                Write-MachineHealthLog "first_run_proposed_winget_client_module todo_path=$todoPath"
            }
        } catch {
            Write-MachineHealthLog "first_run_proposal_failed $($_.Exception.Message)"
        }
    }

    $severityCounts = @{}
    $totalBySeverity = @{ OK = 0; INFO = 0; WARN = 0; CRIT = 0; UNKNOWN = 0 }
    foreach ($r in $checkResults) {
        $cat = $r.category
        if (-not $severityCounts.ContainsKey($cat)) {
            $severityCounts[$cat] = @{ OK = 0; INFO = 0; WARN = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $severityCounts[$cat][$r.severity]++
        $totalBySeverity[$r.severity]++
    }

    $succeededCount = @($remediationAttempts | Where-Object succeeded).Count
    $remediationCounts = @{
        attempted = $remediationAttempts.Count
        succeeded = $succeededCount
        failed    = $remediationAttempts.Count - $succeededCount
    }

    $runEnd = Get-Date
    $durationSeconds = [math]::Round(($runEnd - $runStart).TotalSeconds, 1)

    $urlsCalled = @()
    if ($runLog) {
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
    }

    $snapshot = New-RunSnapshot -RunId $runId -HostName $hostname -OsVersion $osVersion -Elevated $elevated `
        -RunMode $RunMode -DryRun $effectiveDry -Checks @($checkResults) -Remediations @($remediationAttempts) `
        -DiscoveredChecks @($discoveredChecks) -UrlsCalled @($urlsCalled) -DurationSeconds $durationSeconds

    $latestPath = Join-Path $stateDir 'latest.json'
    if ($stateWritable) {
        $snapshot | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $latestPath -Encoding utf8 -Force
        Write-MachineHealthLog "wrote_latest_json path=$latestPath"
    }

    # Compact history line -- extract scalar detail properties per check into
    # top_metrics so subsequent runs can detect trend context. Keys use the
    # "{checkId}.{detailKey}" convention documented in reference/shared/output-schema.md.
    $topMetrics = ConvertTo-TopMetric -CheckResults $checkResults
    # Final (post-trend, post-clamp) severity per successfully-run check: the
    # custom-check clamp counts clean runs from this map.
    $checkSeverities = [ordered]@{}
    foreach ($r in $checkResults) {
        if ($ranCheckIds -contains $r.id) { $checkSeverities[$r.id] = $r.severity }
    }

    $historyLine = [ordered]@{
        run_id             = $runId
        hostname           = $hostname
        os                 = 'windows'
        elevated           = $elevated
        severity_counts    = $severityCounts
        remediation_counts = $remediationCounts
        duration_seconds   = $durationSeconds
        checks_ran         = @($ranCheckIds)
        check_severities   = $checkSeverities
        top_metrics        = $topMetrics
    }
    $historyJson = $historyLine | ConvertTo-Json -Depth 10 -Compress
    if ($stateWritable) {
        Add-Content -LiteralPath $historyPath -Value $historyJson -Encoding utf8
        Write-MachineHealthLog "appended_history path=$historyPath"
    }

    $templatePath = Join-Path $skillRoot 'reference\shared\report-template.md'
    # Per-run (not per-day) filename: a same-day rerun must not overwrite the
    # earlier report, since each run also writes a distinct history entry.
    $reportPath = Join-Path $reportsDir "health-$runStamp.md"

    $oneLine = ("$($totalBySeverity.CRIT) CRIT, $($totalBySeverity.WARN) WARN, " +
        "$($totalBySeverity.INFO) INFO, $($totalBySeverity.OK) OK, " +
        "$($totalBySeverity.UNKNOWN) UNKNOWN")

    function Format-Finding {
        [CmdletBinding()]
        [OutputType([string])]
        param([Parameter(Mandatory = $true)] $Result)

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("#### $(Format-CheckLabel -Id $Result.id -CustomIds $customIds) - $($Result.summary)")
        $lines.Add('')
        $lines.Add("**Severity:** $($Result.severity)")
        $lines.Add('')
        $hasHistory = $Result.PSObject.Properties['trend'] -and $Result.trend -and $Result.trend.last_run
        if ($Result.severity -in @('WARN', 'CRIT') -and -not $hasHistory) {
            $lines.Add('_No trend history for this check; single reading._')
            $lines.Add('')
        }
        if ($Result.notes) {
            $lines.Add("_Note: $($Result.notes)_")
            $lines.Add('')
        }
        $detailTable = ConvertTo-DetailMarkdown -Detail $Result.detail
        if ($detailTable) {
            $lines.Add($detailTable)
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
            ForEach-Object { "- **$(Format-CheckLabel -Id $_.id -CustomIds $customIds)** - $($_.summary)" }) -join "`n"
    if (-not $okList) { $okList = '_none_' }

    $glanceRows = @($checkResults | ForEach-Object {
            "| $($_.category) | $(Format-CheckLabel -Id $_.id -CustomIds $customIds) | **$($_.severity)** | $($_.summary) | $(Format-TrendCell -Result $_) |"
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
            } elseif (-not $stateWritable) {
                'state folder under a cloud sync root'
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
    $openQuestions = Get-OpenQuestionsMarkdown -QueuedTitle $queuedTodoTitles.ToArray() -TodoPath $todoPath

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
        Write-Output ($stateWritable ? "  snapshot: $latestPath" : '  snapshot: not written (state folder under a cloud sync root)')
    } else {
        $snapshot | ConvertTo-Json -Depth 20
    }
} finally {
    if ($runLock) { $runLock.Dispose() }
    foreach ($k in $logDefaultKeys) {
        if ($savedLogDefaults.ContainsKey($k)) {
            $PSDefaultParameterValues[$k] = $savedLogDefaults[$k]
        } else {
            $PSDefaultParameterValues.Remove($k)
        }
    }
}
