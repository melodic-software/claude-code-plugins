#Requires -Version 7.4
<#
.SYNOPSIS
Monthly machine-health checkup for the Task Scheduler fallback: runs the audit
in print mode and records whether it really ran.

.DESCRIPTION
/machine-health:setup writes this file to <StateBase>/scheduler/monthly-run.ps1,
with its plugin root written in, beside scheduled-settings.json, and creates the
task that runs it. It refuses to run from any folder not named scheduler, or
before setup wrote the root in, so the copy in the plugin install never runs.
<StateBase> is the parent of that folder, and the run starts there.

The audit runs in dontAsk mode. Its allow rules are Read, Write or Edit of
<StateBase>/TODO.md (the one Edit(/TODO.md) rule covers both tools), and two
commands through the Bash tool, each matched exactly as audit SKILL.md prints it
for --scheduled, with the plugin root, state folder and report folder setup wrote
in (the PowerShell tool approves no pwsh call by rule). pwsh reading a script from stdin (-File -),
WebFetch and WebSearch are denied, and no MCP server loads.
scheduled-settings.json adds deny rules for git, gh, download commands and the
tools that write or act outside TODO.md; a deny beats every allow rule,
the owner's own included. Anything else is denied instead of prompting, unless
the owner's own settings allow it.

A plugin update moves the plugin root, and a changed report_dir option moves the
report folder. The next run's audit commands then no longer match the allow
rules and are denied, so the run fails; once the old root is gone the wrapper
refuses to start. Rerunning setup's schedule step rewrites the copy.

The run counts as ok only when all of these hold: claude exits 0 within the
timeout, its JSON result has is_error false, the result's first line is the
short report's fixed first line naming latest.json's run_id, and that run_id
is later than this wrapper's start. An exit code alone is not trusted: print
mode can exit 0 without running the skill.

Writes, under <StateBase>/logs/: monthly-run-<runStamp>.status.json with
{ ok, exit_code, is_error, marker_found, latest_newer, timed_out,
streams_incomplete }, written whole under a temporary name and then renamed,
plus whatever the run printed to stdout (.stdout.json) and stderr (.stderr.log,
which opens with the claude executable the wrapper resolved).
streams_incomplete is true when a process the run left behind still held its
output open after the wait below. setup check reports the newest status file.
Exits 0 when ok, 1 otherwise, 2 when misplaced or not written by setup.

.PARAMETER ClaudeCommand
The claude executable, optionally followed by leading arguments. Tests pass a
shim here.

.PARAMETER TimeoutSeconds
How long the run may take before its process tree is stopped.

.PARAMETER StreamWaitSeconds
How long to keep reading output after the run exits or is stopped.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()] [string[]] $ClaudeCommand = @('claude'),
    [ValidateRange(1, 86400)] [int] $TimeoutSeconds = 2700,
    [ValidateRange(1, 600)] [int] $StreamWaitSeconds = 30
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ((Split-Path -Leaf $PSScriptRoot) -cne 'scheduler') {
    Write-Error "monthly-run.ps1 runs only from <StateBase>/scheduler/, where /machine-health:setup copies it; found in '$PSScriptRoot'." -ErrorAction Continue
    exit 2
}

# Setup writes its ${CLAUDE_PLUGIN_ROOT}, ${CLAUDE_PLUGIN_DATA} and report_dir option (empty when
# unset) over these tokens when it installs the copy, as the scheduled audit will type them.
$pluginRoot = '__PLUGIN_ROOT__'
$stateRoot = '__STATE_ROOT__'
$reportRoot = '__REPORT_ROOT__'
if ($pluginRoot -ceq ('__PLUGIN' + '_ROOT__')) {
    Write-Error 'monthly-run.ps1 runs only as written by /machine-health:setup schedule, which fills in the plugin root.' -ErrorAction Continue
    exit 2
}

$stateBase = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $stateBase 'logs'
$settingsPath = Join-Path $PSScriptRoot 'scheduled-settings.json'
$marker = 'machine-health checkup '
# Exact commands, no wildcard: any other argument, such as another -StateBase whose catalog
# overlay names its own check scripts, matches no rule and is denied.
$scripts = "$pluginRoot/skills/audit/scripts/windows"
$outputArg = if ($reportRoot) { "-OutputBase '$reportRoot' " } else { '' }
$shellRules = "Bash(pwsh -NoProfile -File '$scripts/Invoke-MachineHealthCheck.ps1' $outputArg-StateBase '$stateRoot' -RunMode on-demand -SampleSeconds 60 -SkipBanner)",
    "Bash(pwsh -NoProfile -File '$scripts/Format-ShortReport.ps1' -LatestPath '$stateRoot/state/latest.json')"
# Each tool list is variadic, so an option follows each one.
$auditArgs = @('-p', '/machine-health:audit on-demand --scheduled', '--permission-mode', 'dontAsk', '--settings', $settingsPath,
    '--allowedTools', 'Read', 'Edit(/TODO.md)') + $shellRules +
    @('--disallowedTools', 'WebFetch', 'WebSearch', 'Bash(pwsh -NoProfile -File - *)', 'PowerShell(pwsh -NoProfile -File - *)',
    '--strict-mcp-config', '--output-format', 'json')

$start = [DateTimeOffset]::Now
$runStamp = $start.UtcDateTime.ToString('yyyy-MM-ddTHHmmssfffZ', [Globalization.CultureInfo]::InvariantCulture)
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$logPrefix = Join-Path $logsDir "monthly-run-$runStamp"

# A string JSON value as written, or $null; JsonNode never turns a date-shaped string into a DateTime.
function Get-JsonString($Node) {
    if ($Node -is [System.Text.Json.Nodes.JsonValue] -and $Node.GetValueKind() -eq 'String') { $Node.GetValue[string]() } else { $null }
}

$status = [ordered]@{ ok = $false; exit_code = $null; is_error = $null; marker_found = $false; latest_newer = $false
    timed_out = $false; streams_incomplete = $false }
$text = @{ out = [System.Text.StringBuilder]::new(); err = [System.Text.StringBuilder]::new() }
$pending = @{}
$process = $null
try {
    foreach ($path in "$scripts/Invoke-MachineHealthCheck.ps1", "$scripts/Format-ShortReport.ps1") {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "$path is gone, so a plugin update moved the plugin root; rerun /machine-health:setup schedule."
        }
    }
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw "$settingsPath is missing, so the run would lack its deny rules; rerun /machine-health:setup schedule."
    }
    $exe = Get-Command -Name $ClaudeCommand[0] -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $allArgs = @($ClaudeCommand | Select-Object -Skip 1) + $auditArgs
    $viaCmd = $exe.Source -match '\.(cmd|bat)$'
    [void]$text.err.AppendLine("monthly-run: claude is $($exe.Source)$($viaCmd ? ', a batch file that cmd.exe runs' : '')")
    # cmd.exe expands %...% even inside quotes, and reads & | < > ^ in an unquoted argument as syntax.
    if ($viaCmd -and @($allArgs -match '[%&|<>^"]').Count) {
        throw 'an argument holds a character cmd.exe would rewrite (% & | < > ^ ")'
    }
    $psi = [System.Diagnostics.ProcessStartInfo]::new($exe.Source)
    foreach ($a in $allArgs) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $stateBase
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)

    # Chunked reads on this thread: whatever arrived is kept even when a process the run left
    # behind holds a stream open past the exit, and the wait for the rest is bounded.
    $readers = @{ out = $process.StandardOutput; err = $process.StandardError }
    $buffers = @{ out = [char[]]::new(4096); err = [char[]]::new(4096) }
    foreach ($k in $readers.Keys) { $pending[$k] = $readers[$k].ReadAsync($buffers[$k], 0, $buffers[$k].Length) }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $drainBy = $null
    while ($true) {
        $now = [DateTime]::UtcNow
        if ($null -eq $drainBy -and -not $process.HasExited -and $now -ge $deadline) {
            $status.timed_out = $true
            $process.Kill($true)
        }
        if ($null -eq $drainBy -and ($status.timed_out -or $process.HasExited)) { $drainBy = $now.AddSeconds($StreamWaitSeconds) }
        $late = $null -ne $drainBy -and $now -ge $drainBy
        if ($pending.Count -eq 0) {
            if ($process.HasExited -or $late) { break }
            [void]$process.WaitForExit(200)
            continue
        }
        if ($late) { $status.streams_incomplete = $true; break }
        $keys = @($pending.Keys)
        $done = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@(foreach ($k in $keys) { $pending[$k] }), 200)
        if ($done -lt 0) { continue }
        $k = $keys[$done]
        $read = $pending[$k].GetAwaiter().GetResult()
        if ($read -eq 0) {
            $pending.Remove($k)
        } else {
            [void]$text[$k].Append($buffers[$k], 0, $read)
            $pending[$k] = $readers[$k].ReadAsync($buffers[$k], 0, $buffers[$k].Length)
        }
    }
    if (-not $status.timed_out) { $status.exit_code = $process.ExitCode }
} catch {
    [void]$text.err.Append("monthly-run: $($_.Exception.Message)")
}
$stdout = $text.out.ToString()

$runId = $null
try {
    $latestPath = Join-Path $stateBase 'state/latest.json'
    $stream = [System.IO.File]::Open($latestPath, 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
    try { $latestText = [System.IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
    $runId = Get-JsonString ([System.Text.Json.Nodes.JsonNode]::Parse($latestText)['run_id'])
    $status.latest_newer = $null -ne $runId -and
        [DateTimeOffset]::Parse($runId, [Globalization.CultureInfo]::InvariantCulture) -gt $start
} catch {
    [void]$text.err.Append("`nmonthly-run: latest.json run_id unreadable: $($_.Exception.Message)")
}

try {
    $reply = [System.Text.Json.Nodes.JsonNode]::Parse($stdout)
    if ($reply -is [System.Text.Json.Nodes.JsonObject]) {
        $isError = $reply['is_error']
        if ($isError -is [System.Text.Json.Nodes.JsonValue] -and $isError.GetValueKind() -in 'True', 'False') {
            $status.is_error = $isError.GetValue[bool]()
        }
        $result = Get-JsonString $reply['result']
        if ($null -ne $result -and $null -ne $runId) {
            $firstLine = ($result -split "`n", 2)[0].TrimEnd("`r")
            $status.marker_found = [regex]::IsMatch($firstLine, '^' + [regex]::Escape($marker) + '\S+ ' + [regex]::Escape($runId) + '\z')
        }
    }
} catch {
    [void]$text.err.Append("`nmonthly-run: stdout is not the JSON result: $($_.Exception.Message)")
}

$status.ok = $status.exit_code -eq 0 -and $status.is_error -eq $false -and $status.marker_found -and $status.latest_newer

[System.IO.File]::WriteAllText("$logPrefix.stdout.json", $stdout)
[System.IO.File]::WriteAllText("$logPrefix.stderr.log", $text.err.ToString())
# Written whole, then renamed, so a reader never sees a half-written status file.
[System.IO.File]::WriteAllText("$logPrefix.status.json.tmp", ($status | ConvertTo-Json))
[System.IO.File]::Move("$logPrefix.status.json.tmp", "$logPrefix.status.json")
# A read still pending on a stream held open elsewhere could block disposal; the process exit frees it.
if ($process -and $pending.Count -eq 0) { $process.Dispose() }
exit ($status.ok ? 0 : 1)
