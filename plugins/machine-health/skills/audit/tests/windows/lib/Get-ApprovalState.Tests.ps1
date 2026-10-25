#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-ApprovalState.ps1 -- the reader, which
reads only approvals.json, and the Test-ApprovalGranted helper.

.DESCRIPTION
Every run consults approvals.json before dispatching any remediation. These
tests pin the fail-safe posture: missing files, empty files, invalid JSON,
and schema violations all produce a default "nothing
approved" state rather than throwing.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ApprovalState.ps1' -MockHelpers
}

Describe 'Get-ApprovalState' -Tag 'lib' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-approvals'
        $script:stateDir = Join-Path $script:tmpDir 'state'
        $script:approvalsPath = Join-Path $script:stateDir 'approvals.json'
        $script:todoPath = Join-Path $script:tmpDir 'TODO.md'
        $script:logPath = Join-Path $script:tmpDir 'run.log'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    Context 'fail-safe defaults' {
        It 'returns defaults when approvals.json is missing' {
            $state = Get-ApprovalState -StateDir $script:stateDir
            $state.schema_version | Should -Be '1.0'
            @($state.remediations.PSObject.Properties).Count | Should -Be 0
        }

        It 'creates the state directory if it does not exist' {
            Test-Path -LiteralPath $script:stateDir | Should -BeFalse
            $null = Get-ApprovalState -StateDir $script:stateDir
            Test-Path -LiteralPath $script:stateDir | Should -BeTrue
        }

        It 'returns defaults for an empty approvals.json' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            Set-Content -LiteralPath $script:approvalsPath -Value '' -Encoding utf8
            $state = Get-ApprovalState -StateDir $script:stateDir -WarningAction SilentlyContinue
            $state.schema_version | Should -Be '1.0'
        }

        It 'returns defaults for malformed JSON (does not throw)' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            Set-Content -LiteralPath $script:approvalsPath -Value '{broken json' -Encoding utf8
            $state = Get-ApprovalState -StateDir $script:stateDir -WarningAction SilentlyContinue
            $state.schema_version | Should -Be '1.0'
            @($state.remediations.PSObject.Properties).Count | Should -Be 0
        }

        It 'returns defaults for schema-violating JSON (does not throw)' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $bad = '{"schema_version":"99","remediations":{}}'
            Set-Content -LiteralPath $script:approvalsPath -Value $bad -Encoding utf8
            $state = Get-ApprovalState -StateDir $script:stateDir -WarningAction SilentlyContinue
            $state.schema_version | Should -Be '1.0'
        }
    }

    Context 'reading a valid approvals.json' {
        It 'returns the parsed state with approvals intact' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $payload = @{
                schema_version = '1.0'
                remediations   = @{
                    'clear-temp-files' = @{
                        approved    = $true
                        approved_at = '2026-04-22T10:00:00-04:00'
                        notes       = 'enabled after review'
                    }
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $script:approvalsPath -Value $payload -Encoding utf8

            $state = Get-ApprovalState -StateDir $script:stateDir
            $state.remediations.'clear-temp-files'.approved | Should -BeTrue
            $state.remediations.'clear-temp-files'.notes | Should -Be 'enabled after review'
        }

        It 'survives a schema_version v1.0 string with valid content' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $payload = '{"schema_version":"1.0","remediations":{}}'
            Set-Content -LiteralPath $script:approvalsPath -Value $payload -Encoding utf8
            $state = Get-ApprovalState -StateDir $script:stateDir
            $state.schema_version | Should -Be '1.0'
        }
    }

    Context 'reading while another process holds the file' {
        It 'reads while another handle holds the file with ReadWrite' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $payload = '{"schema_version":"1.0","remediations":{"clear-temp-files":{"approved":true}}}'
            Set-Content -LiteralPath $script:approvalsPath -Value $payload -Encoding utf8
            $holder = [System.IO.File]::Open($script:approvalsPath, 'Open', 'ReadWrite', 'ReadWrite')
            try {
                $state = Get-ApprovalState -StateDir $script:stateDir -WarningVariable warned -WarningAction SilentlyContinue
            } finally {
                $holder.Dispose()
            }
            $warned | Should -BeNullOrEmpty
            $state.remediations.'clear-temp-files'.approved | Should -BeTrue
        }
    }

    Context 'a checked TODO.md beside the state folder' {
        It 'returns the default state, approves nothing and writes no approvals.json' {
            Set-Content -LiteralPath $script:todoPath -Value '- [x] restart-stopped-service' -Encoding utf8

            $state = Get-ApprovalState -StateDir $script:stateDir -LogPath $script:logPath

            @($state.remediations.PSObject.Properties).Count | Should -Be 0
            Test-ApprovalGranted -State $state -RemediationId 'restart-stopped-service' | Should -BeFalse
            Test-Path -LiteralPath $script:approvalsPath | Should -BeFalse
        }
    }
}

Describe 'Test-ApprovalGranted' -Tag 'lib' {
    It 'returns true for an explicitly approved remediation' {
        $state = [pscustomobject]@{
            schema_version = '1.0'
            remediations   = [pscustomobject]@{
                'clear-temp-files' = [pscustomobject]@{ approved = $true }
            }
        }
        Test-ApprovalGranted -State $state -RemediationId 'clear-temp-files' | Should -BeTrue
    }

    It 'returns false for an explicitly unapproved remediation' {
        $state = [pscustomobject]@{
            schema_version = '1.0'
            remediations   = [pscustomobject]@{
                'clear-temp-files' = [pscustomobject]@{ approved = $false }
            }
        }
        Test-ApprovalGranted -State $state -RemediationId 'clear-temp-files' | Should -BeFalse
    }

    It 'returns false for a remediation id not present in the map' {
        $state = [pscustomobject]@{
            schema_version = '1.0'
            remediations   = [pscustomobject]@{}
        }
        Test-ApprovalGranted -State $state -RemediationId 'clear-temp-files' | Should -BeFalse
    }

    It 'returns false for a null state' {
        Test-ApprovalGranted -State $null -RemediationId 'clear-temp-files' | Should -BeFalse
    }
}

Describe 'Get-ServiceExclusion' -Tag 'lib' {
    It 'returns the service_exclusions list from a loaded approvals.json' {
        $state = '{"schema_version":"1.0","remediations":{},"check_overrides":{"services":{"service_exclusions":["Spooler","WSearch"]}}}' |
            ConvertFrom-Json
        @(Get-ServiceExclusion -State $state) | Should -Be @('Spooler', 'WSearch')
    }

    It 'returns an empty list when check_overrides is absent' {
        @(Get-ServiceExclusion -State (New-DefaultApprovalState)).Count | Should -Be 0
    }

    It 'returns an empty list when the services override has no exclusions' {
        $state = '{"schema_version":"1.0","remediations":{},"check_overrides":{"services":{}}}' |
            ConvertFrom-Json
        @(Get-ServiceExclusion -State $state).Count | Should -Be 0
    }

    It 'returns an empty list for a null state' {
        @(Get-ServiceExclusion -State $null).Count | Should -Be 0
    }
}
