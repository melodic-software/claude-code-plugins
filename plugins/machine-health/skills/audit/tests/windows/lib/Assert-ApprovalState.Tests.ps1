#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Assert-ApprovalState.ps1.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-ApprovalState.ps1')

    function New-ValidState {
        param([hashtable] $Overrides = @{})
        $base = [pscustomobject]@{
            schema_version = '1.0'
            remediations   = [pscustomobject]@{
                'clear-temp-files' = [pscustomobject]@{
                    approved    = $true
                    approved_at = '2026-04-22T10:00:00-04:00'
                }
            }
        }
        foreach ($k in $Overrides.Keys) {
            $base | Add-Member -NotePropertyName $k -NotePropertyValue $Overrides[$k] -Force
        }
        return $base
    }
}

Describe 'Assert-ApprovalState' -Tag 'lib' {
    Context 'valid states' {
        It 'accepts a minimal valid state (empty remediations map)' {
            $state = [pscustomobject]@{
                schema_version = '1.0'
                remediations   = [pscustomobject]@{}
            }
            Assert-ApprovalState $state | Should -BeTrue
        }

        It 'accepts a state with one remediation entry' {
            Assert-ApprovalState (New-ValidState) | Should -BeTrue
        }

        It 'accepts a state with a migration block' {
            $state = New-ValidState -Overrides @{
                migration = [pscustomobject]@{
                    migrated_from_todo_md = $true
                    migrated_at           = '2026-04-22T10:00:00-04:00'
                    source_checksum       = 'abc123'
                }
            }
            Assert-ApprovalState $state | Should -BeTrue
        }
    }

    Context 'invalid states' {
        It 'rejects null input' {
            { Assert-ApprovalState $null } | Should -Throw -ExpectedMessage '*is null*'
        }

        It 'rejects missing schema_version' {
            $state = [pscustomobject]@{ remediations = [pscustomobject]@{} }
            { Assert-ApprovalState $state } | Should -Throw -ExpectedMessage "*missing required field 'schema_version'*"
        }

        It 'rejects missing remediations' {
            $state = [pscustomobject]@{ schema_version = '1.0' }
            { Assert-ApprovalState $state } | Should -Throw -ExpectedMessage "*missing required field 'remediations'*"
        }

        It 'rejects unsupported schema_version' {
            $state = [pscustomobject]@{
                schema_version = '2.0'
                remediations   = [pscustomobject]@{}
            }
            { Assert-ApprovalState $state } | Should -Throw -ExpectedMessage "*schema_version '2.0' is not supported*"
        }

        It 'rejects an entry missing approved' {
            $state = [pscustomobject]@{
                schema_version = '1.0'
                remediations   = [pscustomobject]@{
                    'clear-temp-files' = [pscustomobject]@{ notes = 'forgot approved' }
                }
            }
            { Assert-ApprovalState $state } |
                Should -Throw -ExpectedMessage "*missing required field 'approved'*"
        }

        It 'rejects an entry with non-boolean approved' {
            $state = [pscustomobject]@{
                schema_version = '1.0'
                remediations   = [pscustomobject]@{
                    'clear-temp-files' = [pscustomobject]@{ approved = 'yes please' }
                }
            }
            { Assert-ApprovalState $state } |
                Should -Throw -ExpectedMessage '*approved must be a boolean*'
        }

        It 'rejects a migration block with non-boolean migrated_from_todo_md' {
            $state = New-ValidState -Overrides @{
                migration = [pscustomobject]@{ migrated_from_todo_md = 'yes' }
            }
            { Assert-ApprovalState $state } |
                Should -Throw -ExpectedMessage '*migrated_from_todo_md must be a boolean*'
        }
    }
}
