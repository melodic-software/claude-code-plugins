#Requires -Version 7.4
<#
.SYNOPSIS
Prints the short run report, at most 12 lines, from state/latest.json.

.DESCRIPTION
The audit skill relays this output verbatim as its closing message, and the
monthly wrapper looks for the fixed first line, `machine-health checkup <host>
<run_id>`. Every line passes through Format-MachineText, so no machine-derived
string (host, summary, path) can add a line or forge the first one.

Lines: the fixed first line; elevation and run mode; severity counts and the
delta against the prior run in state/history.jsonl; the worst three CRIT or
WARN summaries; the intruder headline; the largest unmuted folder; the report
and decision-page paths of this run.

Exits 1, after the fixed first line and the reason, when latest.json is
missing or unreadable.

.PARAMETER LatestPath
Path to <StateBase>/state/latest.json.

.PARAMETER OutputBase
The report root the run used; when given, the report path is printed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $LatestPath,
    [string] $OutputBase
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$libRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libRoot 'New-FindingItem.ps1')
. (Join-Path $libRoot 'Read-SharedText.ps1')
. (Join-Path $libRoot 'Read-HistoryJsonl.ps1')
. (Join-Path $libRoot 'Get-RunDelta.ps1')

$marker = 'machine-health checkup'
$worstShown = 3
$severityOrder = @('CRIT', 'WARN', 'UNKNOWN', 'INFO', 'OK')
$readOk = @('ok', 'absent')

function Get-Field($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

# A history run_id arrives as a DateTime or a string; either way, its instant in UTC ticks.
function Get-Instant($Value) {
    try {
        if ($Value -is [datetime]) { return ([DateTimeOffset]$Value).UtcTicks }
        [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcTicks
    } catch { $null }
}

$lines = [System.Collections.Generic.List[string]]::new()

$latest = $null
$failure = $null
if (-not (Test-Path -LiteralPath $LatestPath -PathType Leaf)) {
    $failure = "latest.json not found at $LatestPath; the run wrote no state (see its report and output)."
} else {
    try {
        $text = Read-SharedText -Path $LatestPath
        $latest = $text | ConvertFrom-Json
        # JsonNode keeps run_id as written; ConvertFrom-Json turns a date-shaped string into a DateTime.
        $runNode = [System.Text.Json.Nodes.JsonNode]::Parse($text)['run_id']
        if ($runNode -isnot [System.Text.Json.Nodes.JsonValue] -or $runNode.GetValueKind() -ne 'String') { throw 'no run_id' }
        $runId = $runNode.GetValue[string]()
        $runAt = [DateTimeOffset]::Parse($runId, [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        $failure = "latest.json unreadable at ${LatestPath}: $($_.Exception.Message)"
    }
}

if ($failure) {
    $lines.Add("$marker $([Environment]::MachineName) no-run-id")
    $lines.Add($failure)
} else {
    $checks = @(Get-Field $latest 'checks' | Where-Object { $null -ne $_ })
    $lines.Add("$marker $(Get-Field $latest 'hostname') $runId")
    $lines.Add("elevated: $((Get-Field $latest 'elevated') ? 'yes' : 'no'), mode: $(Get-Field $latest 'run_mode')")

    # latest.json carries no severity counts, and this run's own history line is
    # already appended, so the prior run is the newest line with another run_id.
    $counts = @{}
    foreach ($s in $severityOrder) { $counts[$s] = @($checks | Where-Object { (Get-Field $_ 'severity') -eq $s }).Count }
    $prior = @(Read-HistoryJsonl -Path (Join-Path (Split-Path -Parent $LatestPath) 'history.jsonl') |
            Where-Object { (Get-Instant (Get-Field $_ 'run_id')) -ne $runAt.UtcTicks })
    $delta = Get-RunDelta -HistoryTail $prior -CurrentSeverityCounts @{ all = $counts }
    $lines.Add("severity: $(($severityOrder | ForEach-Object { "$_ $($counts[$_])" }) -join ', ') (delta: $delta)")

    $worst = @(@(foreach ($s in 'CRIT', 'WARN') { $checks | Where-Object { (Get-Field $_ 'severity') -eq $s } }) |
            Select-Object -First $worstShown)
    if ($worst.Count -eq 0) { $lines.Add('no WARN or CRIT findings') }
    foreach ($c in $worst) { $lines.Add("[$(Get-Field $c 'severity')] $(Get-Field $c 'id'): $(Get-Field $c 'summary')") }

    $byId = @{}
    foreach ($c in $checks) { $byId[[string](Get-Field $c 'id')] = $c }
    function Get-Headline([string] $Id, [string] $StateField, [string] $CountField, [string] $Noun, [string] $Subject) {
        if (-not $byId.ContainsKey($Id)) { return "$Subject not read (check not run)" }
        $detail = Get-Field $byId[$Id] 'detail'
        $state = Get-Field $detail $StateField
        $count = Get-Field $detail $CountField
        if ($state -notin $readOk -or $null -eq $count) { return "$Subject not read ($state)" }
        "$count $Noun"
    }
    $headlines = @(
        @{ Id = 'defender'; StateField = 'events_read_state'; CountField = 'recent_threat_count'; Noun = 'Defender detections'; Subject = 'detections' }
        @{ Id = 'network-listeners'; StateField = 'read_state'; CountField = 'exposed_unsigned_count'; Noun = 'exposed listeners unsigned or user-writable'; Subject = 'listeners' }
        @{ Id = 'defender-exclusions'; StateField = 'list_state'; CountField = 'unexpected_path_count'; Noun = 'unexpected path exclusions'; Subject = 'exclusions' }
    ) | ForEach-Object { Get-Headline @_ }
    $lines.Add('intruder: ' + ($headlines -join '; '))

    $folders = @(Get-Field (Get-Field $byId['storage-top-n'] 'detail') 'items' |
            Where-Object { $_ -and -not (Get-Field $_ 'muted') -and $null -ne (Get-Field $_ 'logical_bytes') } |
            Sort-Object { [long]$_.logical_bytes } -Descending)
    $lines.Add('largest folder: ' + ($folders.Count -gt 0 ? (Get-Field $folders[0] 'title') : 'none listed'))

    $stamp = $runAt.UtcDateTime.ToString('yyyy-MM-ddTHHmmssfffZ', [Globalization.CultureInfo]::InvariantCulture)
    if ($OutputBase) {
        $report = Join-Path $OutputBase "reports/health-$stamp.md"
        $lines.Add('report: ' + ((Test-Path -LiteralPath $report) ? $report : 'not found'))
    }
    $page = Join-Path (Split-Path -Parent (Split-Path -Parent $LatestPath)) "views/checkup-$stamp.html"
    $lines.Add('page: ' + ((Test-Path -LiteralPath $page) ? $page : 'not built'))
}

foreach ($line in $lines) { Format-MachineText $line }
exit ($failure ? 1 : 0)
