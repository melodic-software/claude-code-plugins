#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for the monthly wrapper template, skills/setup/templates/monthly-run.ps1,
with `claude` replaced by a shim process.

.DESCRIPTION
Each case copies the template to <StateBase>/scheduler/, where setup puts it,
and runs it. The shim is a pwsh script started as a real child
process, so the timeout can stop it. It records its arguments and, per
MH_SHIM_MODE, writes latest.json, prints a `claude -p --output-format json`
result and exits. Its result text is the real Format-ShortReport.ps1 output
over that latest.json, so these tests fail when the script's first line and
the wrapper's marker check drift apart.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1"
    $script:Template = Join-Path (Split-Path -Parent $script:SkillRoot) 'setup\templates\monthly-run.ps1'
    . (Join-Path (Split-Path -Parent $script:SkillRoot) 'setup\scripts\Install-MonthlyRun.ps1')
    $script:ShortReport = Join-Path $script:SkillRoot 'scripts\windows\Format-ShortReport.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:OldRunId = '2020-01-01T00:00:00.0000000+00:00'

    $script:Shim = Join-Path $TestDrive 'claude-shim.ps1'
    Set-Content -LiteralPath $script:Shim -Encoding utf8 -Value @'
$ErrorActionPreference = 'Stop'
if ($args[0] -eq 'plugin') { $env:MH_PLUGIN_LIST; exit 0 }
$args | ConvertTo-Json | Set-Content -LiteralPath 'shim-args.json'
@{ session = $env:PLUGIN_PROFILES_SESSION; file = $env:PLUGIN_PROFILES_SESSION_FILE } | ConvertTo-Json | Set-Content -LiteralPath 'shim-env.json'
Set-Content -LiteralPath 'shim-pid.txt' -Value $PID
$fresh = { New-Item -ItemType Directory -Force -Path 'state' | Out-Null
    @{ run_id = (Get-Date).ToString('o'); hostname = 'TESTHOST' } | ConvertTo-Json | Set-Content -LiteralPath 'state/latest.json' }
$short = { param($Latest = 'state/latest.json') (& $env:MH_SHORT_REPORT -LatestPath $Latest) -join "`n" }
$reply = { param($IsError, $Text) @{ type = 'result'; is_error = $IsError; result = $Text } | ConvertTo-Json -Compress }
switch ($env:MH_SHIM_MODE) {
    'ok' { & $fresh; & $reply $false (& $short); exit 0 }
    'no-marker' { & $fresh; & $reply $false 'Unknown skill: machine-health:audit'; exit 0 }
    'no-run-id' { & $fresh; & $reply $false (& $short 'state/missing.json'); exit 0 }
    'text-first' { & $fresh; & $reply $false ("Done.`n" + (& $short)); exit 0 }
    'stale' { & $reply $false (& $short); exit 0 }
    'not-json' { & $fresh; & $short; exit 0 }
    'fail' { & $fresh; & $reply $true (& $short); exit 1 }
    'exit1-no-error' { & $fresh; & $reply $false (& $short); exit 1 }
    'exit0-error' { & $fresh; & $reply $true (& $short); exit 0 }
    'orphan' {
        & $fresh; & $reply $false (& $short)
        $child = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 90' -PassThru -NoNewWindow
        Set-Content -LiteralPath 'shim-child-pid.txt' -Value $child.Id
        exit 0
    }
    'hang' {
        $child = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120' -PassThru -NoNewWindow
        Set-Content -LiteralPath 'shim-child-pid.txt' -Value $child.Id
        Start-Sleep 120
    }
}
'@

    # Stands in for plugin-profiles' profiles.mjs: logs its arguments and prints the launch
    # result, or refuses with exit 1 when MH_PROFILES_RC=1.
    $script:ProfilesRoot = Join-Path $TestDrive 'plugin-profiles'
    New-Item -ItemType Directory -Force -Path (Join-Path $script:ProfilesRoot 'scripts') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:ProfilesRoot 'scripts/profiles.mjs') -Encoding utf8 -Value @'
import { appendFileSync } from "node:fs";
const args = process.argv.slice(2);
appendFileSync("profiles-args.log", args.join(" ") + "\n");
if (process.env.MH_PROFILES_RC === "1") {
  console.error("not launched: profile " + args[1] + " switches on a plugin missing a required prerequisite, and nobody is there to decide.");
  process.exit(1);
}
console.log(JSON.stringify({ profile: args[1], argv: ["env", "-u", "PLUGIN_PROFILES_SESSION", "-u", "PLUGIN_PROFILES_SESSION_FILE", "claude", "--settings", "session-" + args[1] + ".json"] }));
'@
    $script:PluginList = ConvertTo-Json -Compress -InputObject @(
        @{ id = 'other@m'; enabled = $true; installPath = '/nowhere' },
        @{ id = 'plugin-profiles@m'; enabled = $true; installPath = $script:ProfilesRoot })

    function Get-ExpectedArgumentList {
        @('-p', '/machine-health:audit on-demand --scheduled', '--permission-mode', 'auto', '--output-format', 'json')
    }

    function Invoke-Wrapper([string] $Mode, [string[]] $Command, [int] $TimeoutSeconds = 120, [int] $StreamWaitSeconds = 30,
        [string] $Folder = 'scheduler', [string] $PluginProfile, [string] $PluginList = $script:PluginList, [string] $ProfilesRc = '0') {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $base 'state') | Out-Null
        @{ run_id = $script:OldRunId; hostname = 'TESTHOST' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $base 'state\latest.json')
        $wrapper = (Install-MonthlyRun -StateBase $base).WrapperPath
        if ($Folder -cne 'scheduler') {
            $moved = Join-Path (New-Item -ItemType Directory -Path (Join-Path $base $Folder)) 'monthly-run.ps1'
            Move-Item -LiteralPath $wrapper -Destination $moved
            $wrapper = $moved
        }
        if (-not $Command) { $Command = @($script:Pwsh, '-NoProfile', '-File', $script:Shim) }

        $saved = $env:MH_SHIM_MODE, $env:MH_SHORT_REPORT, $env:MH_PLUGIN_LIST, $env:MH_PROFILES_RC, $env:PLUGIN_PROFILES_SESSION, $env:PLUGIN_PROFILES_SESSION_FILE
        $env:MH_SHIM_MODE = $Mode
        $env:MH_SHORT_REPORT = $script:ShortReport
        $env:MH_PLUGIN_LIST = $PluginList
        $env:MH_PROFILES_RC = $ProfilesRc
        # A run started from a profiled shell inherits both markers.
        $env:PLUGIN_PROFILES_SESSION = 'outer'
        $env:PLUGIN_PROFILES_SESSION_FILE = 'outer.json'
        $profileArg = $PluginProfile ? @{ PluginProfile = $PluginProfile } : @{}
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        Push-Location $base
        try {
            $global:LASTEXITCODE = 0
            $output = & $wrapper -ClaudeCommand $Command -TimeoutSeconds $TimeoutSeconds -StreamWaitSeconds $StreamWaitSeconds @profileArg 2>&1
            $exit = $LASTEXITCODE
        } finally {
            Pop-Location
            $env:MH_SHIM_MODE, $env:MH_SHORT_REPORT, $env:MH_PLUGIN_LIST, $env:MH_PROFILES_RC, $env:PLUGIN_PROFILES_SESSION, $env:PLUGIN_PROFILES_SESSION_FILE = $saved
        }
        $statusFiles = @(Get-ChildItem -LiteralPath (Join-Path $base 'logs') -Filter 'monthly-run-*.status.json' -ErrorAction SilentlyContinue)
        $stderrFile = Get-ChildItem -LiteralPath (Join-Path $base 'logs') -Filter 'monthly-run-*.stderr.log' -ErrorAction SilentlyContinue | Select-Object -First 1
        [pscustomobject]@{
            Base        = $base
            ExitCode    = $exit
            Seconds     = $clock.Elapsed.TotalSeconds
            Output      = ($output | Out-String)
            Stderr      = $stderrFile ? (Get-Content -Raw -LiteralPath $stderrFile.FullName) : $null
            LogNames    = @(Get-ChildItem -LiteralPath (Join-Path $base 'logs') -Name -ErrorAction SilentlyContinue)
            StatusFiles = $statusFiles
            Status      = $statusFiles.Count -eq 1 ? (Get-Content -Raw -LiteralPath $statusFiles[0].FullName | ConvertFrom-Json -AsHashtable) : $null
        }
    }
}

Describe 'monthly-run wrapper' -Tag 'lib' {
    It 'counts a run ok when it exits 0, is_error is false, the short report opens the result and latest.json is newer' {
        $r = Invoke-Wrapper 'ok'
        $r.StatusFiles.Count | Should -Be 1
        $r.StatusFiles[0].Name | Should -Match '^monthly-run-\d{4}-\d{2}-\d{2}T\d{9}Z\.status\.json$'
        $r.Status | Should -Not -BeNullOrEmpty
        @($r.Status.Keys | Sort-Object) | Should -Be @('exit_code', 'is_error', 'latest_newer', 'marker_found', 'ok', 'streams_incomplete', 'timed_out')
        $r.Status.ok | Should -BeTrue
        $r.Status.exit_code | Should -Be 0
        $r.Status.is_error | Should -BeFalse
        $r.Status.marker_found | Should -BeTrue
        $r.Status.latest_newer | Should -BeTrue
        $r.Status.timed_out | Should -BeFalse
        $r.Status.streams_incomplete | Should -BeFalse
        $r.ExitCode | Should -Be 0
    }

    It 'runs the scheduled audit in print mode in auto mode, from the state root' {
        $r = Invoke-Wrapper 'ok'
        $shimArgs = @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json)
        $shimArgs | Should -Be (Get-ExpectedArgumentList)
        Join-Path $r.Base 'logs' | Get-ChildItem -Filter 'monthly-run-*.stdout.json' | Should -HaveCount 1
        $r.LogNames | Where-Object { $_ -like '*.tmp' } | Should -BeNullOrEmpty
    }

    It 'records which claude it ran in the stderr log' {
        $r = Invoke-Wrapper 'ok'
        $r.Stderr | Should -Match ([regex]::Escape("monthly-run: claude is $script:Pwsh"))
    }

    It 'passes every argument intact through a .cmd claude, which cmd.exe re-parses' {
        $cmd = Join-Path $TestDrive 'claude-shim.cmd'
        Set-Content -LiteralPath $cmd -Value "@`"$script:Pwsh`" -NoProfile -File `"$script:Shim`" %*"
        $r = Invoke-Wrapper 'ok' -Command @($cmd)
        $r.Status.ok | Should -BeTrue
        @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json) | Should -Be (Get-ExpectedArgumentList)
        $r.Stderr | Should -Match 'cmd\.exe'
    }

    It 'refuses a .cmd claude when an argument holds a character cmd.exe would expand' {
        $cmd = Join-Path $TestDrive 'claude-shim.cmd'
        Set-Content -LiteralPath $cmd -Value "@`"$script:Pwsh`" -NoProfile -File `"$script:Shim`" %*"
        $r = Invoke-Wrapper 'ok' -Command @($cmd, '--note=%TEMP%')
        $r.StatusFiles.Count | Should -Be 1
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -BeNullOrEmpty
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
        $r.Stderr | Should -Match 'cmd\.exe'
    }

    It 'fails an exit-0 run whose result lacks the marker' {
        $r = Invoke-Wrapper 'no-marker'
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -Be 0
        $r.Status.marker_found | Should -BeFalse
        $r.Status.latest_newer | Should -BeTrue
        $r.ExitCode | Should -Be 1
    }

    It 'fails a result whose first line is the short report failure line, which names no run id' {
        $r = Invoke-Wrapper 'no-run-id'
        $r.Status.ok | Should -BeFalse
        $r.Status.marker_found | Should -BeFalse
        $r.Status.latest_newer | Should -BeTrue
    }

    It 'fails a result whose marker line is not its first line' {
        $r = Invoke-Wrapper 'text-first'
        $r.Status.ok | Should -BeFalse
        $r.Status.marker_found | Should -BeFalse
    }

    It 'fails a run that leaves a latest.json older than the wrapper start' {
        $r = Invoke-Wrapper 'stale'
        $r.Status.ok | Should -BeFalse
        $r.Status.marker_found | Should -BeTrue
        $r.Status.latest_newer | Should -BeFalse
    }

    It 'fails a non-zero exit' {
        $r = Invoke-Wrapper 'fail'
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -Be 1
        $r.Status.is_error | Should -BeTrue
    }

    It 'fails an exit-1 run even when is_error is false and the marker and a newer latest.json are there' {
        $r = Invoke-Wrapper 'exit1-no-error'
        $r.Status.exit_code | Should -Be 1
        $r.Status.is_error | Should -BeFalse
        $r.Status.marker_found | Should -BeTrue
        $r.Status.latest_newer | Should -BeTrue
        $r.Status.ok | Should -BeFalse
        $r.ExitCode | Should -Be 1
    }

    It 'fails an exit-0 run whose result is an error even with the marker and a newer latest.json' {
        $r = Invoke-Wrapper 'exit0-error'
        $r.Status.exit_code | Should -Be 0
        $r.Status.is_error | Should -BeTrue
        $r.Status.marker_found | Should -BeTrue
        $r.Status.latest_newer | Should -BeTrue
        $r.Status.ok | Should -BeFalse
    }

    It 'fails output that is not the JSON result, with is_error unknown' {
        $r = Invoke-Wrapper 'not-json'
        $r.Status.ok | Should -BeFalse
        $r.Status.is_error | Should -BeNullOrEmpty
        $r.Status.marker_found | Should -BeFalse
    }

    It 'stops the process tree when the run outlives the timeout' {
        $r = Invoke-Wrapper 'hang' -TimeoutSeconds 10
        $r.Status.timed_out | Should -BeTrue
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -BeNullOrEmpty
        foreach ($file in 'shim-pid.txt', 'shim-child-pid.txt') {
            $id = [int](Get-Content -LiteralPath (Join-Path $r.Base $file))
            Get-Process -Id $id -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    It 'returns within the stream wait, keeping what the run printed, when a leftover process holds stdout open' {
        $r = Invoke-Wrapper 'orphan' -StreamWaitSeconds 3
        try {
            $r.Seconds | Should -BeLessThan 45
            $r.StatusFiles.Count | Should -Be 1
            $r.Status.streams_incomplete | Should -BeTrue
            $r.Status.exit_code | Should -Be 0
            $r.Status.marker_found | Should -BeTrue
            $r.Status.ok | Should -BeTrue
            Join-Path $r.Base 'logs' | Get-ChildItem -Filter 'monthly-run-*.stdout.json' |
                Get-Content -Raw | Should -Match '"is_error":false'
        } finally {
            $childFile = Join-Path $r.Base 'shim-child-pid.txt'
            if (Test-Path -LiteralPath $childFile) {
                Stop-Process -Id ([int](Get-Content -LiteralPath $childFile)) -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'still writes a status file when claude cannot be found' {
        $r = Invoke-Wrapper 'ok' -Command @('mh-no-such-command-for-tests')
        $r.StatusFiles.Count | Should -Be 1
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -BeNullOrEmpty
        $r.Status.timed_out | Should -BeFalse
    }

    It 'refuses to run outside a scheduler folder and writes nothing' {
        $r = Invoke-Wrapper 'ok' -Folder 'templates'
        $r.ExitCode | Should -Be 2
        Join-Path $r.Base 'logs' | Should -Not -Exist
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
    }
}

# Not Windows-only: these run on every platform the suite runs on.
Describe 'monthly-run wrapper in a plugin profile' -Tag 'lib' {
    It 'starts the run with the profile launch arguments before the audit arguments, with both markers cleared and no env' {
        $r = Invoke-Wrapper 'ok' -PluginProfile 'build'
        $r.Status.ok | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $r.Base 'profiles-args.log') |
            Should -Be "launch build --folder $($r.Base) --unattended --json"
        @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json) |
            Should -Be (@('--settings', 'session-build.json') + (Get-ExpectedArgumentList))
        $seen = Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-env.json') | ConvertFrom-Json
        $seen.session | Should -BeNullOrEmpty
        $seen.file | Should -BeNullOrEmpty
        $r.Stderr | Should -Match ([regex]::Escape('monthly-run: profile build adds --settings session-build.json and clears PLUGIN_PROFILES_SESSION, PLUGIN_PROFILES_SESSION_FILE'))
    }

    It 'runs as before with no profile named: no profile launch, the audit arguments alone, the environment untouched' {
        $r = Invoke-Wrapper 'ok'
        $r.Status.ok | Should -BeTrue
        Join-Path $r.Base 'profiles-args.log' | Should -Not -Exist
        @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json) | Should -Be (Get-ExpectedArgumentList)
        (Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-env.json') | ConvertFrom-Json).session | Should -Be 'outer'
    }

    It 'does not start the run when plugin-profiles is not installed and enabled' {
        $list = ConvertTo-Json -Compress -InputObject @(@{ id = 'plugin-profiles@m'; enabled = $false; installPath = $script:ProfilesRoot })
        $r = Invoke-Wrapper 'ok' -PluginProfile 'build' -PluginList $list
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 1
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
        $r.Stderr | Should -Match ([regex]::Escape("plugin-profiles is not installed and enabled, so profile 'build' was not applied and the run did not start"))
    }

    It 'does not start the run when the profile launch refuses, and logs its reason' {
        $r = Invoke-Wrapper 'ok' -PluginProfile 'build' -ProfilesRc '1'
        $r.Status.ok | Should -BeFalse
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
        $r.Stderr | Should -Match "profile 'build' was not applied and the run did not start: profiles\.mjs launch exited 1: .*missing a required prerequisite"
    }

    It 'rejects a profile name that is not a plain word' {
        { Invoke-Wrapper 'ok' -PluginProfile 'build" /f' } | Should -Throw
    }
}
