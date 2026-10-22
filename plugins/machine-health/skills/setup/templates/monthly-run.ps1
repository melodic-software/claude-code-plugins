#Requires -Version 7.4
<#
.SYNOPSIS
Monthly machine-health checkup for the Task Scheduler fallback: runs the audit
in print mode and records whether it really ran.

.DESCRIPTION
/machine-health:setup copies this file to <StateBase>/scheduler/monthly-run.ps1
and creates the task that runs it; it refuses to run from any folder not named
scheduler, so the copy in the plugin install never runs. <StateBase> is the
parent of that folder, and the run starts there.

The run counts as ok only when all of these hold: claude exits 0 within the
timeout, its JSON result has is_error false, the result holds the short
report's fixed first line, and state/latest.json has a run_id later than this
wrapper's start. An exit code alone is not trusted: print mode can exit 0
without running the skill.

Writes, under <StateBase>/logs/: monthly-run-<runStamp>.status.json with
{ ok, exit_code, is_error, marker_found, latest_newer, timed_out }, plus the
run's stdout (.stdout.json) and stderr (.stderr.log). setup check reports the
newest status file. Exits 0 when ok, 1 otherwise, 2 when misplaced.

.PARAMETER ClaudeCommand
The claude executable, optionally followed by leading arguments. Tests pass a
shim here.

.PARAMETER TimeoutSeconds
How long the run may take before its process tree is stopped.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()] [string[]] $ClaudeCommand = @('claude'),
    [ValidateRange(1, 86400)] [int] $TimeoutSeconds = 2700
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ((Split-Path -Leaf $PSScriptRoot) -cne 'scheduler') {
    Write-Error "monthly-run.ps1 runs only from <StateBase>/scheduler/, where /machine-health:setup copies it; found in '$PSScriptRoot'." -ErrorAction Continue
    exit 2
}

$stateBase = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $stateBase 'logs'
$marker = 'machine-health checkup '
$auditArgs = @('-p', '/machine-health:audit on-demand --scheduled',
    '--permission-mode', 'auto', '--permission-prompts', 'none', '--output-format', 'json')

$start = [DateTimeOffset]::Now
$runStamp = $start.UtcDateTime.ToString('yyyy-MM-ddTHHmmssfffZ', [Globalization.CultureInfo]::InvariantCulture)
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$logPrefix = Join-Path $logsDir "monthly-run-$runStamp"

# A string JSON value as written, or $null; JsonNode never turns a date-shaped string into a DateTime.
function Get-JsonString($Node) {
    if ($Node -is [System.Text.Json.Nodes.JsonValue] -and $Node.GetValueKind() -eq 'String') { $Node.GetValue[string]() } else { $null }
}

$status = [ordered]@{ ok = $false; exit_code = $null; is_error = $null; marker_found = $false; latest_newer = $false; timed_out = $false }
$stdout = ''
$stderr = ''
try {
    $exe = Get-Command -Name $ClaudeCommand[0] -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $psi = [System.Diagnostics.ProcessStartInfo]::new($exe.Source)
    foreach ($a in @($ClaudeCommand | Select-Object -Skip 1) + $auditArgs) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $stateBase
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    try {
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if ($process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.WaitForExit()
            $status.exit_code = $process.ExitCode
        } else {
            $status.timed_out = $true
            $process.Kill($true)
            $process.WaitForExit()
        }
        $stdout = $outTask.Result
        $stderr = $errTask.Result
    } finally {
        $process.Dispose()
    }
} catch {
    $stderr += "monthly-run: $($_.Exception.Message)"
}

try {
    $reply = [System.Text.Json.Nodes.JsonNode]::Parse($stdout)
    if ($reply -is [System.Text.Json.Nodes.JsonObject]) {
        $isError = $reply['is_error']
        if ($isError -is [System.Text.Json.Nodes.JsonValue] -and $isError.GetValueKind() -in 'True', 'False') {
            $status.is_error = $isError.GetValue[bool]()
        }
        $result = Get-JsonString $reply['result']
        $status.marker_found = $null -ne $result -and $result.Contains($marker, [StringComparison]::Ordinal)
    }
} catch {
    $stderr += "`nmonthly-run: stdout is not the JSON result: $($_.Exception.Message)"
}

try {
    $latestPath = Join-Path $stateBase 'state/latest.json'
    $stream = [System.IO.File]::Open($latestPath, 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
    try { $latestText = [System.IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
    $runId = Get-JsonString ([System.Text.Json.Nodes.JsonNode]::Parse($latestText)['run_id'])
    $status.latest_newer = $null -ne $runId -and
        [DateTimeOffset]::Parse($runId, [Globalization.CultureInfo]::InvariantCulture) -gt $start
} catch {
    $stderr += "`nmonthly-run: latest.json run_id unreadable: $($_.Exception.Message)"
}

$status.ok = $status.exit_code -eq 0 -and $status.is_error -eq $false -and $status.marker_found -and
    $status.latest_newer -and -not $status.timed_out

[System.IO.File]::WriteAllText("$logPrefix.stdout.json", $stdout)
[System.IO.File]::WriteAllText("$logPrefix.stderr.log", $stderr)
[System.IO.File]::WriteAllText("$logPrefix.status.json", ($status | ConvertTo-Json))
exit ($status.ok ? 0 : 1)
