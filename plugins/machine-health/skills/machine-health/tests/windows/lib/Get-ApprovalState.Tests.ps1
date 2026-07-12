#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-ApprovalState.ps1 -- reader + TODO.md
one-shot migration path + Test-ApprovalGranted helper.

.DESCRIPTION
Every run consults approvals.json before dispatching any remediation. These
tests pin the fail-safe posture: missing files, empty files, invalid JSON,
schema violations, and migration failures all produce a default "nothing
approved" state rather than throwing.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Get-ApprovalState.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force
}

Describe 'Get-ApprovalState' -Tag 'lib' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-approvals'
        $script:stateDir = Join-Path $script:tmpDir 'state'
        $script:todoPath = Join-Path $script:tmpDir 'TODO.md'
        $script:logPath = Join-Path $script:tmpDir 'run.log'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    Context 'fail-safe defaults' {
        It 'returns defaults when approvals.json is missing and no TODO.md is provided' {
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
            Set-Content -LiteralPath (Join-Path $script:stateDir 'approvals.json') -Value '' -Encoding utf8
            $state = Get-ApprovalState -StateDir $script:stateDir -WarningAction SilentlyContinue
            $state.schema_version | Should -Be '1.0'
        }

        It 'returns defaults for malformed JSON (does not throw)' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:stateDir 'approvals.json') `
                -Value '{broken json' -Encoding utf8
            $state = Get-ApprovalState -StateDir $script:stateDir -WarningAction SilentlyContinue
            $state.schema_version | Should -Be '1.0'
            @($state.remediations.PSObject.Properties).Count | Should -Be 0
        }

        It 'returns defaults for schema-violating JSON (does not throw)' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $bad = '{"schema_version":"99","remediations":{}}'
            Set-Content -LiteralPath (Join-Path $script:stateDir 'approvals.json') `
                -Value $bad -Encoding utf8
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
            Set-Content -LiteralPath (Join-Path $script:stateDir 'approvals.json') `
                -Value $payload -Encoding utf8

            $state = Get-ApprovalState -StateDir $script:stateDir
            $state.remediations.'clear-temp-files'.approved | Should -BeTrue
            $state.remediations.'clear-temp-files'.notes | Should -Be 'enabled after review'
        }

        It 'survives a schema_version v1.0 string with valid content' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $payload = '{"schema_version":"1.0","remediations":{}}'
            Set-Content -LiteralPath (Join-Path $script:stateDir 'approvals.json') `
                -Value $payload -Encoding utf8
            $state = Get-ApprovalState -StateDir $script:stateDir
            $state.schema_version | Should -Be '1.0'
        }
    }

    Context 'migration from legacy TODO.md' {
        It 'writes approvals.json when TODO.md has [x] checkboxes and approvals.json is missing' {
            $todo = @'
# Remediation checklist

- [x] Enable Restart-StoppedService
- [ ] Enable Clear-TempFiles
'@
            Set-Content -LiteralPath $script:todoPath -Value $todo -Encoding utf8

            $state = Get-ApprovalState -StateDir $script:stateDir `
                -TodoPath $script:todoPath -LogPath $script:logPath

            $state.remediations.'restart-stopped-service'.approved | Should -BeTrue
            $state.remediations.PSObject.Properties['clear-temp-files'] | Should -BeNullOrEmpty
            $state.migration.migrated_from_todo_md | Should -BeTrue
            $state.migration.source_checksum | Should -Not -BeNullOrEmpty

            Test-Path -LiteralPath (Join-Path $script:stateDir 'approvals.json') | Should -BeTrue
        }

        It 'records approved_by and a timestamp in migrated entries' {
            Set-Content -LiteralPath $script:todoPath `
                -Value '- [x] Clear-TempFiles' -Encoding utf8

            $state = Get-ApprovalState -StateDir $script:stateDir -TodoPath $script:todoPath

            $state.remediations.'clear-temp-files'.approved_by | Should -Not -BeNullOrEmpty
            $state.remediations.'clear-temp-files'.approved_at | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It 'does NOT overwrite an existing approvals.json with a migration' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $existing = '{"schema_version":"1.0","remediations":{"clear-temp-files":{"approved":false}}}'
            $approvalsPath = Join-Path $script:stateDir 'approvals.json'
            Set-Content -LiteralPath $approvalsPath -Value $existing -Encoding utf8

            Set-Content -LiteralPath $script:todoPath `
                -Value '- [x] Clear-TempFiles' -Encoding utf8

            $state = Get-ApprovalState -StateDir $script:stateDir -TodoPath $script:todoPath
            $state.remediations.'clear-temp-files'.approved | Should -BeFalse
            $state.PSObject.Properties['migration'] | Should -BeNullOrEmpty
        }

        It 'returns defaults when TODO.md exists but has no [x] markers' {
            Set-Content -LiteralPath $script:todoPath `
                -Value '- [ ] Clear-TempFiles (pending review)' -Encoding utf8

            $state = Get-ApprovalState -StateDir $script:stateDir -TodoPath $script:todoPath
            $state.schema_version | Should -Be '1.0'
            @($state.remediations.PSObject.Properties).Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $script:stateDir 'approvals.json') | Should -BeFalse
        }

        It 'logs a migration event when LogPath is provided' {
            Set-Content -LiteralPath $script:todoPath `
                -Value '- [x] Clear-TempFiles' -Encoding utf8

            $null = Get-ApprovalState -StateDir $script:stateDir `
                -TodoPath $script:todoPath -LogPath $script:logPath

            $logContent = Get-Content -LiteralPath $script:logPath -Raw
            $logContent | Should -Match 'approvals_migrated'
            $logContent | Should -Match 'TODO\.md'
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
