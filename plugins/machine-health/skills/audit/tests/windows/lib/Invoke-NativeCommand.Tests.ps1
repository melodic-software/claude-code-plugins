#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Invoke-NativeCommand.ps1.

The recording stub is pwsh itself: one child process records the argv it
actually received. Every other native-tool suite mocks this command.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Invoke-NativeCommand.ps1' -MockHelpers

    $script:recordScript = Join-Path $PSScriptRoot '..\..\fixtures\windows\native-command\record-argv.ps1'

    function Read-RecordedArgv {
        $log = $env:NATIVE_ARGV_LOG
        if (-not $log -or -not (Test-Path -LiteralPath $log)) { return @() }
        $text = [System.IO.File]::ReadAllText($log)
        if ([string]::IsNullOrWhiteSpace($text)) { return @() }
        return @($text -split "`r?`n" | Where-Object { $_ } | ForEach-Object {
                [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
            })
    }
}

Describe 'Invoke-NativeCommand' -Tag 'lib' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-native'
        $env:NATIVE_ARGV_LOG = Join-Path $script:tmpDir 'argv.txt'
        $env:NATIVE_ARGV_EXIT = '0'
    }

    AfterEach {
        Remove-Item Env:NATIVE_ARGV_LOG, Env:NATIVE_ARGV_EXIT -ErrorAction SilentlyContinue
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    It 'hands a comma-bearing query to the process as one argv entry' {
        $result = Invoke-NativeCommand -Name 'pwsh' -DiscardStdErr -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-File', $script:recordScript,
            '--query-gpu=name,driver_version',
            '--format=csv,noheader'
        )

        $result.status | Should -Be 'Ok'
        $result.source | Should -Be 'pwsh'
        $result.exit_code | Should -Be 0
        $result.output | Should -Be 'recorded'

        $argv = @(Read-RecordedArgv)
        $argv[-2] | Should -BeExactly '--query-gpu=name,driver_version'
        $argv[-1] | Should -BeExactly '--format=csv,noheader'
        # #3370 spread this one flag into `--query-gpu=name` plus `driver_version`.
        $argv | Should -Not -Contain '--query-gpu=name'
        $argv | Should -Not -Contain 'driver_version'
    }

    It 'records a spread argument vector as separate entries, so the regression stays visible' {
        $null = Invoke-NativeCommand -Name 'pwsh' -DiscardStdErr -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-File', $script:recordScript,
            '--query-gpu=name', 'driver_version', '--format=csv', 'noheader'
        )

        $argv = @(Read-RecordedArgv)
        $argv[-4] | Should -BeExactly '--query-gpu=name'
        $argv[-3] | Should -BeExactly 'driver_version'
        $argv[-2] | Should -BeExactly '--format=csv'
        $argv[-1] | Should -BeExactly 'noheader'
    }

    It 'reports a tool that is not on PATH with source absent and does not throw' {
        $result = Invoke-NativeCommand -Name 'machine-health-not-on-path' -ArgumentList @('--query')
        $result.status | Should -Be 'Absent'
        $result.source | Should -Be 'absent'
        $result.exit_code | Should -BeNullOrEmpty
        $result.output | Should -Be ''
        $result.error | Should -BeNullOrEmpty
    }

    It 'routes a non-zero exit to status NonZero and still returns the output' {
        $env:NATIVE_ARGV_EXIT = '2'
        $result = Invoke-NativeCommand -Name 'pwsh' -DiscardStdErr -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-File', $script:recordScript
        )
        $result.status | Should -Be 'NonZero'
        $result.source | Should -Be 'pwsh'
        $result.exit_code | Should -Be 2
        $result.output | Should -Be 'recorded'
        $result.error | Should -BeNullOrEmpty
    }

    It 'reports Failed when the resolved tool cannot be started' {
        Mock Get-Command {
            [pscustomobject]@{ Source = (Join-Path $script:tmpDir 'missing-binary') }
        } -ParameterFilter { $Name -eq 'ghost-tool' }

        $result = Invoke-NativeCommand -Name 'ghost-tool' -ArgumentList @('a')
        $result.status | Should -Be 'Failed'
        $result.source | Should -Be 'ghost-tool'
        $result.exit_code | Should -BeNullOrEmpty
        $result.output | Should -Be ''
        $result.error | Should -Not -BeNullOrEmpty
    }

    It 'merges stderr into output unless DiscardStdErr is set' {
        $speaker = Join-Path $script:tmpDir 'speak.ps1'
        @'
Write-Output 'out-line'
[Console]::Error.WriteLine('err-line')
exit 0
'@ | Set-Content -LiteralPath $speaker -Encoding utf8NoBOM

        $merged = Invoke-NativeCommand -Name 'pwsh' -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-File', $speaker
        )
        $merged.status | Should -Be 'Ok'
        $merged.output | Should -Match 'out-line'
        $merged.output | Should -Match 'err-line'

        $discarded = Invoke-NativeCommand -Name 'pwsh' -DiscardStdErr -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-File', $speaker
        )
        $discarded.output | Should -Be 'out-line'
        $discarded.output | Should -Not -Match 'err-line'
    }
}
