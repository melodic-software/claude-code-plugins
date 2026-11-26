#Requires -Version 7.4
<#
.SYNOPSIS
Monthly machine-health checkup for the Task Scheduler fallback: runs the audit
in print mode and records whether it really ran.

.DESCRIPTION
/machine-health:setup copies this file to <StateBase>/scheduler/monthly-run.ps1
and creates the task that runs it. It refuses to run from any folder not named
scheduler, so the copy in the plugin install never runs. <StateBase> is the
parent of that folder, and the run starts there.

The audit runs in auto mode, so it can research new findings on the web
(https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode).

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
Exits 0 when ok, 1 otherwise, 2 when misplaced.

.PARAMETER ClaudeCommand
The claude executable, optionally followed by leading arguments. Tests pass a
shim here.

.PARAMETER TimeoutSeconds
How long the run may take before its process tree is stopped.

.PARAMETER StreamWaitSeconds
How long to keep reading output after the run exits or is stopped.

.PARAMETER PluginProfile
A plugin profile to start the run in. Each run asks the enabled plugin-profiles
install, found through `claude plugin list --json`, for
`profiles.mjs launch <name> --folder <StateBase> --unattended --json`, removes
from the run's environment each variable its argv clears with `env -u`, and
passes the argv's remaining claude arguments before the audit's, the same way
on every platform. When plugin-profiles is missing, the launch refuses, or the
profile leaves machine-health off (the launch result's enabledPlugins, which the
profile wins), the run does not start and the reason goes to the stderr log.
Without it the run starts as it always has.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()] [string[]] $ClaudeCommand = @('claude'),
    [ValidateRange(1, 86400)] [int] $TimeoutSeconds = 5400,
    [ValidateRange(1, 600)] [int] $StreamWaitSeconds = 30,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')] [string] $PluginProfile
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
$auditArgs = @('-p', '/machine-health:audit on-demand --scheduled', '--permission-mode', 'auto', '--output-format', 'json')

$start = [DateTimeOffset]::Now
$runStamp = $start.UtcDateTime.ToString('yyyy-MM-ddTHHmmssfffZ', [Globalization.CultureInfo]::InvariantCulture)
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$logPrefix = Join-Path $logsDir "monthly-run-$runStamp"

function Get-JsonString($Node) {
    if ($Node -is [System.Text.Json.Nodes.JsonValue] -and $Node.GetValueKind() -eq 'String') { $Node.GetValue[string]() } else { $null }
}

$status = [ordered]@{ ok = $false; exit_code = $null; is_error = $null; marker_found = $false; latest_newer = $false
    timed_out = $false; streams_incomplete = $false }
$text = @{ out = [System.Text.StringBuilder]::new(); err = [System.Text.StringBuilder]::new() }
$pending = @{}
$process = $null
try {
    $exe = Get-Command -Name $ClaudeCommand[0] -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $lead = @($ClaudeCommand | Select-Object -Skip 1)
    $unset = @()
    $profileArgs = @()
    if ($PluginProfile) {
        $list = (& $exe.Source @lead plugin list --json 2>$null) -join "`n" | ConvertFrom-Json -AsHashtable
        $root = foreach ($p in @($list)) {
            if ($p -is [System.Collections.IDictionary] -and "$($p['id'])" -like 'plugin-profiles@*' -and $p['enabled'] -eq $true -and $p['installPath']) { $p['installPath']; break }
        }
        if (-not $root) { throw "plugin-profiles is not installed and enabled, so profile '$PluginProfile' was not applied and the run did not start" }
        $node = Get-Command -Name node -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $launched = & $node.Source (Join-Path $root 'scripts/profiles.mjs') launch $PluginProfile --folder $stateBase --unattended --json 2>&1
        $launchRc = $LASTEXITCODE
        $said = @($launched | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        if ($launchRc -ne 0) { throw "profile '$PluginProfile' was not applied and the run did not start: profiles.mjs launch exited ${launchRc}: $($said -join '; ')" }
        $result = @($launched | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n" | ConvertFrom-Json -AsHashtable
        $enabled = $result['enabledPlugins']
        if ($enabled -isnot [System.Collections.IDictionary]) {
            throw "profile '$PluginProfile' was not applied and the run did not start: profiles.mjs launch reported no enabledPlugins to check machine-health against; update plugin-profiles"
        }
        if (-not @($enabled.Keys | Where-Object { ($_ -ceq 'machine-health' -or $_ -clike 'machine-health@*') -and $enabled[$_] -eq $true }).Count) {
            throw "profile '$PluginProfile' leaves machine-health off, so the run would not reach /machine-health:audit and did not start; name a profile that includes machine-health"
        }
        $argv = @($result['argv'])
        $i = 0
        if ($argv.Count -and $argv[0] -ceq 'env') {
            $i = 1
            while ($i + 1 -lt $argv.Count -and $argv[$i] -ceq '-u') { $unset += $argv[$i + 1]; $i += 2 }
        }
        if ($i -ge $argv.Count -or $argv[$i] -cne 'claude' -or @($argv | Where-Object { $_ -isnot [string] }).Count) {
            throw "profile '$PluginProfile' was not applied and the run did not start: profiles.mjs launch printed no claude command"
        }
        $profileArgs = @($argv | Select-Object -Skip ($i + 1))
        foreach ($line in $said) { [void]$text.err.AppendLine("monthly-run: profiles.mjs: $line") }
        [void]$text.err.AppendLine("monthly-run: profile $PluginProfile adds $($profileArgs -join ' ') and clears $($unset -join ', ')")
    }
    $allArgs = $lead + $profileArgs + $auditArgs
    $viaCmd = $exe.Source -match '\.(cmd|bat)$'
    [void]$text.err.AppendLine("monthly-run: claude is $($exe.Source)$($viaCmd ? ', a batch file that cmd.exe runs' : '')")
    if ($viaCmd -and @($allArgs -match '[%&|<>^"]').Count) {
        throw 'an argument holds a character cmd.exe would rewrite (% & | < > ^ ")'
    }
    $psi = [System.Diagnostics.ProcessStartInfo]::new($exe.Source)
    foreach ($a in $allArgs) { $psi.ArgumentList.Add($a) }
    foreach ($name in $unset) { [void]$psi.Environment.Remove($name) }
    $psi.WorkingDirectory = $stateBase
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $process = [System.Diagnostics.Process]::Start($psi)

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
    $stream = [System.IO.File]::Open((Join-Path $stateBase 'state/latest.json'), 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
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
[System.IO.File]::WriteAllText("$logPrefix.status.json.tmp", ($status | ConvertTo-Json))
[System.IO.File]::Move("$logPrefix.status.json.tmp", "$logPrefix.status.json")
if ($process -and $pending.Count -eq 0) { $process.Dispose() }
exit ($status.ok ? 0 : 1)
