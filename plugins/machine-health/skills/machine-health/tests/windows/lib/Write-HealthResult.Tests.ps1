#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Write-HealthResult.ps1 (New-HealthResult +
Write-HealthResult) with schema enforcement via Assert-CheckResult.

.DESCRIPTION
The emit pipeline is the contract between every check script and the
orchestrator. Bugs here silently corrupt the report; we validate both shape
(field names, types, defaults) and behavior (JSON round-trip, schema
enforcement at emit time, human-readable fallback).
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Write-HealthResult.ps1')
}

Describe 'New-HealthResult' -Tag 'lib' {
    Context 'defaults' {
        It 'produces a CheckResult with the canonical field set' {
            $result = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                -Severity 'OK' -Summary 'all good'

            $names = $result.PSObject.Properties.Name
            $names | Should -Contain 'id'
            $names | Should -Contain 'category'
            $names | Should -Contain 'os'
            $names | Should -Contain 'ran_at'
            $names | Should -Contain 'severity'
            $names | Should -Contain 'summary'
            $names | Should -Contain 'detail'
            $names | Should -Contain 'commands'
            $names | Should -Contain 'needs_admin'
            $names | Should -Contain 'ran_successfully'
            $names | Should -Contain 'duration_ms'
            $names | Should -Contain 'trend'
            $names | Should -Contain 'notes'
            $names | Should -Contain 'error'
        }

        It 'defaults detail and commands to empty collections' {
            $result = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                -Severity 'OK' -Summary 's'

            $result.detail | Should -BeOfType [hashtable]
            @($result.detail.Keys).Count | Should -Be 0
            @($result.commands).Count | Should -Be 0
        }

        It 'defaults needs_admin and ran_successfully sensibly' {
            $result = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                -Severity 'OK' -Summary 's'
            $result.needs_admin | Should -BeFalse
            $result.ran_successfully | Should -BeTrue
        }

        It 'stamps ran_at in ISO 8601 with offset' {
            $result = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                -Severity 'OK' -Summary 's'
            $result.ran_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?[+-]\d{2}:\d{2}$'
        }
    }

    Context 'validation' {
        It 'rejects an invalid severity at parameter binding' {
            { New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                    -Severity 'BAD' -Summary 's' } | Should -Throw
        }

        It 'rejects an invalid os at parameter binding' {
            { New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'bsd' `
                    -Severity 'OK' -Summary 's' } | Should -Throw
        }
    }

    Context 'mutability after construction' {
        It 'allows duration_ms to be set after construction (caller pattern)' {
            $result = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                -Severity 'OK' -Summary 's'
            $result.duration_ms = 42
            $result.duration_ms | Should -Be 42
        }
    }
}

Describe 'Write-HealthResult' -Tag 'lib' {
    BeforeEach {
        $script:validResult = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
            -Severity 'OK' -Summary 'all good' -DurationMs 15 `
            -Commands @('Get-Volume')
    }

    Context 'JSON mode (default)' {
        It 'emits one compact JSON line on stdout' {
            $out = $script:validResult | Write-HealthResult
            $out | Should -BeOfType [string]
            $out | Should -Not -Match "`n"
            $parsed = $out | ConvertFrom-Json
            $parsed.id | Should -Be 'disk-space'
            $parsed.severity | Should -Be 'OK'
        }

        It 'preserves a single-element commands array as a JSON array (regression)' {
            $out = $script:validResult | Write-HealthResult
            # Raw JSON must contain array brackets around the lone command, not scalar form.
            $out | Should -Match '"commands":\["Get-Volume"\]'
        }

        It 'serializes multiple commands as a JSON array' {
            $multi = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                -Severity 'OK' -Summary 's' -Commands @('Get-Volume', 'Get-PhysicalDisk')
            $out = $multi | Write-HealthResult
            $out | Should -Match '"commands":\["Get-Volume","Get-PhysicalDisk"\]'
        }

        It 'round-trips through ConvertFrom-Json and Assert-CheckResult' {
            $out = $script:validResult | Write-HealthResult
            $parsed = $out | ConvertFrom-Json
            { Assert-CheckResult $parsed } | Should -Not -Throw
        }

        It 'preserves detail depth up to 10 levels' {
            $deep = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
                -Severity 'OK' -Summary 's' `
                -Detail @{ a = @{ b = @{ c = @{ d = @{ e = 'leaf' } } } } }
            $out = $deep | Write-HealthResult
            $parsed = $out | ConvertFrom-Json
            $parsed.detail.a.b.c.d.e | Should -Be 'leaf'
        }
    }

    Context 'schema enforcement at emit time' {
        It 'throws when id is not kebab-case' {
            $bad = [pscustomobject]@{
                id = 'DiskSpace'; category = 'storage'; os = 'windows'
                ran_at = (Get-Date).ToString('o'); severity = 'OK'
                summary = 's'; detail = @{}; commands = @()
                needs_admin = $false; ran_successfully = $true; duration_ms = 1
                trend = $null; notes = $null; error = $null
            }
            { $bad | Write-HealthResult } | Should -Throw -ExpectedMessage '*kebab-case*'
        }

        It 'throws when ran_successfully is false but severity is not UNKNOWN' {
            $bad = [pscustomobject]@{
                id = 'defender'; category = 'security'; os = 'windows'
                ran_at = (Get-Date).ToString('o'); severity = 'OK'
                summary = 's'; detail = @{}; commands = @()
                needs_admin = $false; ran_successfully = $false; duration_ms = 1
                trend = $null; notes = $null; error = 'something'
            }
            { $bad | Write-HealthResult } | Should -Throw -ExpectedMessage '*severity must be UNKNOWN*'
        }

        It 'throws when a required field is missing' {
            $bad = [pscustomobject]@{ id = 'x'; category = 'storage' }
            { $bad | Write-HealthResult } | Should -Throw -ExpectedMessage '*missing required field*'
        }
    }

    Context '-Human mode' {
        It 'emits a "[SEV] id - summary" line' {
            $out = $script:validResult | Write-HealthResult -Human
            ($out -join "`n") | Should -Match '\[OK\] disk-space - all good'
        }

        It 'appends note and error lines when present' {
            $full = New-HealthResult -Id 'defender' -Category 'security' -Os 'windows' `
                -Severity 'UNKNOWN' -Summary 'cmdlet unavailable' `
                -RanSuccessfully $false -ErrorMessage 'Get-MpComputerStatus missing' `
                -Notes 'fallback engaged' -DurationMs 1
            $out = $full | Write-HealthResult -Human
            ($out -join "`n") | Should -Match 'note: fallback engaged'
            ($out -join "`n") | Should -Match 'error: Get-MpComputerStatus missing'
        }
    }
}
