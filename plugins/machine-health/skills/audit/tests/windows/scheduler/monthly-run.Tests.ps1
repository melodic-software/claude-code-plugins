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
result and exits.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1"
    $script:Template = Join-Path (Split-Path -Parent $script:SkillRoot) 'setup\templates\monthly-run.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:OldRunId = '2020-01-01T00:00:00.0000000+00:00'

    $script:Shim = Join-Path $TestDrive 'claude-shim.ps1'
    Set-Content -LiteralPath $script:Shim -Encoding utf8 -Value @'
$ErrorActionPreference = 'Stop'
$args | ConvertTo-Json | Set-Content -LiteralPath 'shim-args.json'
Set-Content -LiteralPath 'shim-pid.txt' -Value $PID
$fresh = { New-Item -ItemType Directory -Force -Path 'state' | Out-Null
    @{ run_id = (Get-Date).ToString('o'); hostname = 'TESTHOST' } | ConvertTo-Json | Set-Content -LiteralPath 'state/latest.json' }
$reply = { param($IsError, $Text) @{ type = 'result'; is_error = $IsError; result = $Text } | ConvertTo-Json -Compress }
switch ($env:MH_SHIM_MODE) {
    'ok' { & $fresh; & $reply $false "machine-health checkup TESTHOST now`nseverity: OK 1"; exit 0 }
    'no-marker' { & $fresh; & $reply $false 'Unknown skill: machine-health:audit'; exit 0 }
    'stale' { & $reply $false 'machine-health checkup TESTHOST old'; exit 0 }
    'not-json' { & $fresh; 'machine-health checkup TESTHOST plain text'; exit 0 }
    'fail' { & $fresh; & $reply $true 'machine-health checkup TESTHOST error'; exit 1 }
    'hang' {
        $child = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120' -PassThru -NoNewWindow
        Set-Content -LiteralPath 'shim-child-pid.txt' -Value $child.Id
        Start-Sleep 120
    }
}
'@

    function Invoke-Wrapper([string] $Mode, [string[]] $Command, [int] $TimeoutSeconds = 120, [string] $Folder = 'scheduler') {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $dir = New-Item -ItemType Directory -Path (Join-Path $base $Folder)
        New-Item -ItemType Directory -Path (Join-Path $base 'state') | Out-Null
        @{ run_id = $script:OldRunId } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $base 'state\latest.json')
        $wrapper = Join-Path $dir 'monthly-run.ps1'
        Copy-Item -LiteralPath $script:Template -Destination $wrapper
        if (-not $Command) { $Command = @($script:Pwsh, '-NoProfile', '-File', $script:Shim) }

        $saved = $env:MH_SHIM_MODE
        $env:MH_SHIM_MODE = $Mode
        try {
            $global:LASTEXITCODE = 0
            $output = & $wrapper -ClaudeCommand $Command -TimeoutSeconds $TimeoutSeconds 2>&1
            $exit = $LASTEXITCODE
        } finally {
            $env:MH_SHIM_MODE = $saved
        }
        $statusFiles = @(Get-ChildItem -LiteralPath (Join-Path $base 'logs') -Filter 'monthly-run-*.status.json' -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Base        = $base
            ExitCode    = $exit
            Output      = ($output | Out-String)
            StatusFiles = $statusFiles
            Status      = $statusFiles.Count -eq 1 ? (Get-Content -Raw -LiteralPath $statusFiles[0].FullName | ConvertFrom-Json -AsHashtable) : $null
        }
    }
}

Describe 'monthly-run wrapper' -Tag 'lib' {
    It 'counts a run ok when it exits 0, is_error is false, the marker is in result and latest.json is newer' {
        $r = Invoke-Wrapper 'ok'
        $r.StatusFiles.Count | Should -Be 1
        $r.StatusFiles[0].Name | Should -Match '^monthly-run-\d{4}-\d{2}-\d{2}T\d{9}Z\.status\.json$'
        $r.Status | Should -Not -BeNullOrEmpty
        @($r.Status.Keys | Sort-Object) | Should -Be @('exit_code', 'is_error', 'latest_newer', 'marker_found', 'ok', 'timed_out')
        $r.Status.ok | Should -BeTrue
        $r.Status.exit_code | Should -Be 0
        $r.Status.is_error | Should -BeFalse
        $r.Status.marker_found | Should -BeTrue
        $r.Status.latest_newer | Should -BeTrue
        $r.Status.timed_out | Should -BeFalse
        $r.ExitCode | Should -Be 0
    }

    It 'runs the scheduled audit in print mode with an explicit permission mode, from the state root' {
        $r = Invoke-Wrapper 'ok'
        $shimArgs = @(Get-Content -Raw -LiteralPath (Join-Path $r.Base 'shim-args.json') | ConvertFrom-Json)
        ($shimArgs -join ' ') | Should -BeExactly '-p /machine-health:audit on-demand --scheduled --permission-mode auto --permission-prompts none --output-format json'
        $shimArgs[1] | Should -BeExactly '/machine-health:audit on-demand --scheduled'
        Join-Path $r.Base 'logs' | Get-ChildItem -Filter 'monthly-run-*.stdout.json' | Should -HaveCount 1
    }

    It 'fails an exit-0 run whose result lacks the marker' {
        $r = Invoke-Wrapper 'no-marker'
        $r.Status.ok | Should -BeFalse
        $r.Status.exit_code | Should -Be 0
        $r.Status.marker_found | Should -BeFalse
        $r.Status.latest_newer | Should -BeTrue
        $r.ExitCode | Should -Be 1
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
