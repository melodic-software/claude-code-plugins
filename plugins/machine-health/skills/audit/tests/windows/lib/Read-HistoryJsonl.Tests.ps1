#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Read-HistoryJsonl.ps1.

.DESCRIPTION
Read-HistoryJsonl is the trend-context loader used by the orchestrator on every
run. Must tolerate: missing file (first run), empty file, blank/whitespace lines,
malformed lines mixed with valid ones, and respect the -Tail window without
throwing. JSONL is append-only so read-side robustness is the correctness bar.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Read-HistoryJsonl.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force
}

Describe 'Read-HistoryJsonl' -Tag 'lib' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-history'
        $script:historyPath = Join-Path $script:tmpDir 'history.jsonl'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    Context 'absent state' {
        It 'returns nothing (empty array) when the file is missing' {
            $result = Read-HistoryJsonl -Path $script:historyPath
            @($result).Count | Should -Be 0
        }

        It 'returns nothing for an empty file' {
            New-Item -ItemType File -Path $script:historyPath -Force | Out-Null
            $result = Read-HistoryJsonl -Path $script:historyPath
            @($result).Count | Should -Be 0
        }

        It 'does not throw when the path is unreadable-shaped' {
            { Read-HistoryJsonl -Path (Join-Path $script:tmpDir 'does-not-exist.jsonl') } |
                Should -Not -Throw
        }
    }

    Context 'valid input' {
        It 'parses a single well-formed line' {
            $payload = '{"run_id":"run-alpha","severity_counts":{"OK":5}}'
            Set-Content -LiteralPath $script:historyPath -Value $payload -Encoding utf8
            $result = @(Read-HistoryJsonl -Path $script:historyPath)
            $result.Count | Should -Be 1
            $result[0].run_id | Should -Be 'run-alpha'
            $result[0].severity_counts.OK | Should -Be 5
        }

        It 'parses multiple lines in order' {
            $lines = @(
                '{"run_id":"2026-04-01T00:00:00","n":1}'
                '{"run_id":"2026-04-08T00:00:00","n":2}'
                '{"run_id":"2026-04-15T00:00:00","n":3}'
            )
            Set-Content -LiteralPath $script:historyPath -Value $lines -Encoding utf8
            $result = Read-HistoryJsonl -Path $script:historyPath
            $result.Count | Should -Be 3
            $result[0].n | Should -Be 1
            $result[2].n | Should -Be 3
        }
    }

    Context 'tail window' {
        It 'respects -Tail to limit lines read' {
            $lines = 1..10 | ForEach-Object { "{`"n`":$_}" }
            Set-Content -LiteralPath $script:historyPath -Value $lines -Encoding utf8

            $result = Read-HistoryJsonl -Path $script:historyPath -Tail 3
            $result.Count | Should -Be 3
            $result[0].n | Should -Be 8
            $result[2].n | Should -Be 10
        }

        It 'defaults to the last 8 lines' {
            $lines = 1..20 | ForEach-Object { "{`"n`":$_}" }
            Set-Content -LiteralPath $script:historyPath -Value $lines -Encoding utf8

            $result = Read-HistoryJsonl -Path $script:historyPath
            $result.Count | Should -Be 8
            $result[0].n | Should -Be 13
        }
    }

    Context 'mixed malformed and valid input' {
        It 'skips blank and whitespace-only lines without warning noise' {
            $lines = @(
                '{"n":1}'
                ''
                '   '
                '{"n":2}'
            )
            Set-Content -LiteralPath $script:historyPath -Value $lines -Encoding utf8

            $result = Read-HistoryJsonl -Path $script:historyPath
            $result.Count | Should -Be 2
            $result[0].n | Should -Be 1
            $result[1].n | Should -Be 2
        }

        It 'skips unparsable JSON lines and keeps the valid ones' {
            $lines = @(
                '{"n":1}'
                'not-json-at-all'
                '{"n":2}'
                '{invalid'
            )
            Set-Content -LiteralPath $script:historyPath -Value $lines -Encoding utf8

            $result = Read-HistoryJsonl -Path $script:historyPath -WarningAction SilentlyContinue
            $result.Count | Should -Be 2
            $result[0].n | Should -Be 1
            $result[1].n | Should -Be 2
        }

        It 'emits a warning for each malformed line' {
            $lines = @(
                '{"n":1}'
                'not-json'
                'still-not-json'
            )
            Set-Content -LiteralPath $script:historyPath -Value $lines -Encoding utf8

            $warnings = @()
            $readParams = @{
                Path            = $script:historyPath
                WarningVariable = 'warnings'
                WarningAction   = 'SilentlyContinue'
            }
            $null = Read-HistoryJsonl @readParams
            $warnings.Count | Should -BeGreaterOrEqual 2
        }
    }
}
