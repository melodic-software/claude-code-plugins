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
    # A plugin root with a space, in the forward-slash form ${CLAUDE_PLUGIN_ROOT} renders in on Windows.
    $script:PluginRoot = (Join-Path $TestDrive 'plugin root').Replace('\', '/')
    $scriptsDir = New-Item -ItemType Directory -Force -Path (Join-Path $TestDrive 'plugin root\skills\audit\scripts\windows')
    foreach ($name in 'Invoke-MachineHealthCheck.ps1', 'Format-ShortReport.ps1') { New-Item -ItemType File -Path (Join-Path $scriptsDir $name) | Out-Null }
    $script:ShortReport = Join-Path $script:SkillRoot 'scripts\windows\Format-ShortReport.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:OldRunId = '2020-01-01T00:00:00.0000000+00:00'

    $script:Shim = Join-Path $TestDrive 'claude-shim.ps1'
    Set-Content -LiteralPath $script:Shim -Encoding utf8 -Value @'
$ErrorActionPreference = 'Stop'
$args | ConvertTo-Json | Set-Content -LiteralPath 'shim-args.json'
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

    # The audit command lines, as audit SKILL.md steps 4 and 8 write them, are the only shell commands allowed.
    function Get-ExpectedArgumentList([string] $Base) {
        $orchestrator = "pwsh -NoProfile -File '$script:PluginRoot/skills/audit/scripts/windows/Invoke-MachineHealthCheck.ps1' " +
            "-StateBase '$Base' -RunMode on-demand -SampleSeconds 60 -SkipBanner"
        $shortReport = "pwsh -NoProfile -File '$script:PluginRoot/skills/audit/scripts/windows/Format-ShortReport.ps1' -LatestPath '$Base/state/latest.json'"
        @('-p', '/machine-health:audit on-demand --scheduled', '--permission-mode', 'dontAsk',
            '--settings', (Join-Path $Base 'scheduler\scheduled-settings.json'),
            '--allowedTools', 'Read', 'Edit(/TODO.md)', "Bash($orchestrator)", "Bash($shortReport)",
            '--disallowedTools', 'WebFetch', 'WebSearch', 'Bash(pwsh -NoProfile -File - *)', 'PowerShell(pwsh -NoProfile -File - *)',
            '--strict-mcp-config', '--output-format', 'json')
    }

    function Invoke-Wrapper([string] $Mode, [string[]] $Command, [int] $TimeoutSeconds = 120, [int] $StreamWaitSeconds = 30,
        [string] $Folder = 'scheduler', [string] $PluginRoot = $script:PluginRoot, [string] $ReportRoot, [switch] $Unrendered,
        [switch] $NoSettings) {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $base 'state') | Out-Null
        @{ run_id = $script:OldRunId; hostname = 'TESTHOST' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $base 'state\latest.json')
        $wrapper = (Install-MonthlyRun -PluginRoot $PluginRoot -StateBase $base -ReportRoot $ReportRoot).WrapperPath
        if ($Unrendered) { Copy-Item -LiteralPath $script:Template -Destination $wrapper -Force }
        if ($NoSettings) { Remove-Item -LiteralPath (Join-Path $base 'scheduler\scheduled-settings.json') }
        if ($Folder -cne 'scheduler') {
            $moved = Join-Path (New-Item -ItemType Directory -Path (Join-Path $base $Folder)) 'monthly-run.ps1'
            Move-Item -LiteralPath $wrapper -Destination $moved
            $wrapper = $moved
        }
        if (-not $Command) { $Command = @($script:Pwsh, '-NoProfile', '-File', $script:Shim) }

        $saved = $env:MH_SHIM_MODE, $env:MH_SHORT_REPORT
        $env:MH_SHIM_MODE = $Mode
        $env:MH_SHORT_REPORT = $script:ShortReport
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $global:LASTEXITCODE = 0
            $output = & $wrapper -ClaudeCommand $Command -TimeoutSeconds $TimeoutSeconds -StreamWaitSeconds $StreamWaitSeconds 2>&1
            $exit = $LASTEXITCODE
        } finally {
            $env:MH_SHIM_MODE, $env:MH_SHORT_REPORT = $saved
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

    It 'runs the scheduled audit in print mode under dontAsk with only the two audit scripts, the deny settings, no web tools and no MCP servers, from the state root' {
        $r = Invoke-Wrapper 'ok'
        $shimArgs = @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json)
        $shimArgs | Should -Be (Get-ExpectedArgumentList $r.Base)
        Join-Path $r.Base 'logs' | Get-ChildItem -Filter 'monthly-run-*.stdout.json' | Should -HaveCount 1
        $r.LogNames | Where-Object { $_ -like '*.tmp' } | Should -BeNullOrEmpty
    }

    It 'allows exactly the two commands audit SKILL.md prints for --scheduled, with the roots setup wrote in, when the report option is <Case>' -ForEach @(
        @{ Case = 'set'; Report = 'D:/Reports/machine health' }
        @{ Case = 'unset'; Report = '' }
    ) {
        $r = Invoke-Wrapper 'ok' -ReportRoot $Report
        $shimArgs = @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json)
        $allowed = $shimArgs[([array]::IndexOf($shimArgs, '--allowedTools') + 1)..([array]::IndexOf($shimArgs, '--disallowedTools') - 1)]
        $rules = @($allowed | Where-Object { $_ -like 'Bash(*' } | ForEach-Object { $_ -replace '^Bash\((.*)\)$', '$1' })
        $skillText = Get-Content -Raw -LiteralPath (Join-Path $script:SkillRoot 'SKILL.md')
        # Typed as step 4 says: the run mode on-demand, and no -OutputBase when the option is unset.
        $commands = @([regex]::Matches($skillText, '(?m)^[ \t]*```text\r?\n[ \t]*(pwsh -NoProfile -File .*)$') | ForEach-Object {
                $c = $_.Groups[1].Value.TrimEnd()
                if (-not $Report) { $c = $c.Replace(" -OutputBase '<report-root>'", '') }
                $c.Replace('${CLAUDE_PLUGIN_ROOT}', $script:PluginRoot).Replace('<state-root>', $r.Base).
                Replace('<report-root>', $Report).Replace('<mode>', 'on-demand')
            })

        $commands.Count | Should -Be 2
        $rules | Should -Be $commands
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
        @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json) | Should -Be (Get-ExpectedArgumentList $r.Base)
        $r.Stderr | Should -Match 'cmd\.exe'
    }

    It 'refuses a .cmd claude when an argument holds a character cmd.exe would expand' {
        # Setup refuses such a character in a root (Assert-ScheduleRoot), so it arrives in a leading argument.
        $cmd = Join-Path $TestDrive 'claude-shim.cmd'
        Set-Content -LiteralPath $cmd -Value "@`"$script:Pwsh`" -NoProfile -File `"$script:Shim`" %*"
        $r = Invoke-Wrapper 'ok' -Command @($cmd, '--note=%TEMP%')
        $r.StatusFiles.Count | Should -Be 1
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -BeNullOrEmpty
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
        $r.Stderr | Should -Match 'cmd\.exe'
    }

    It 'refuses to start without the deny settings file, and says so' {
        $r = Invoke-Wrapper 'ok' -NoSettings
        $r.StatusFiles.Count | Should -Be 1
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -BeNullOrEmpty
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
        $r.Stderr | Should -Match 'scheduled-settings\.json'
    }

    It 'refuses to start once the plugin root it pins no longer holds the audit scripts, naming setup schedule' {
        $r = Invoke-Wrapper 'ok' -PluginRoot (Join-Path $TestDrive 'moved-away').Replace('\', '/')
        $r.StatusFiles.Count | Should -Be 1
        $r.Status.ok | Should -BeFalse
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
        $r.Stderr | Should -Match 'setup schedule'
    }

    It 'refuses a copy setup never rendered, and writes nothing' {
        $r = Invoke-Wrapper 'ok' -Unrendered
        $r.ExitCode | Should -Be 2
        Join-Path $r.Base 'logs' | Should -Not -Exist
        Join-Path $r.Base 'shim-args.json' | Should -Not -Exist
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
