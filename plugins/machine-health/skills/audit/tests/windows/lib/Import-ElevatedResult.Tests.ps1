#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Import-ElevatedResult.ps1. The acceptance rules
(format, ran_at after the file's creation time, Assert-CheckResult) and the one
UNKNOWN elevated-pass note come from reference/windows/elevation-matrix.md,
"How to run elevated".
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Import-ElevatedResult.ps1'

    function Get-CheckResultFixture {
        param([string] $Id, [string] $Category, [string] $Severity, [string] $Summary)
        [pscustomobject]@{
            id = $Id; category = $Category; os = 'windows'; ran_at = '2026-10-21T00:00:00.0000000Z'
            severity = $Severity; summary = $Summary; detail = @{}; commands = @(); needs_admin = $true
            ran_successfully = $true; duration_ms = 5; trend = $null; notes = $null; error = $null
        }
    }

    # Pre-create the file, then write a document whose ran_at sits -OffsetSeconds from
    # the creation time the import reads back.
    function Write-ElevatedResultFixture {
        param(
            [object[]] $Results = @(),
            [string] $Format = 'elevated-result/1',
            [int] $OffsetSeconds = 5
        )
        $path = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        [System.IO.File]::Create($path).Dispose()
        $created = [System.IO.File]::GetCreationTimeUtc($path)
        $doc = [ordered]@{
            format   = $Format
            ran_at   = $created.AddSeconds($OffsetSeconds).ToString('o')
            elevated = $true
            results  = @($Results)
            log      = @()
        }
        [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 10))
        return $path
    }

    function Get-Note {
        param($Import)
        @($Import.Results | Where-Object { $_.id -eq 'elevated-pass' })
    }
}

Describe 'Import-ElevatedResult' -Tag 'lib' {
    BeforeEach {
        $script:standard = @(
            (Get-CheckResultFixture -Id 'disk-space' -Category 'storage' -Severity 'UNKNOWN' -Summary 'standard reading')
            (Get-CheckResultFixture -Id 'services' -Category 'services' -Severity 'OK' -Summary 'services fine')
        )
        $script:elevatedDisk = Get-CheckResultFixture -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Summary 'elevated reading'
    }

    It 'replaces the standard result per check id and lists the replaced ids' {
        $path = Write-ElevatedResultFixture -Results @($script:elevatedDisk)

        $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

        $import.Rejected | Should -BeNullOrEmpty
        @($import.Results).Count | Should -Be 2
        ($import.Results | Where-Object id -EQ 'disk-space').summary | Should -BeExactly 'elevated reading'
        ($import.Results | Where-Object id -EQ 'disk-space').severity | Should -BeExactly 'WARN'
        ($import.Results | Where-Object id -EQ 'services').summary | Should -BeExactly 'services fine'
        @($import.ElevatedChecks) | Should -Be @('disk-space')
        @(Get-Note $import).Count | Should -Be 0
    }

    It 'drops an elevated result for a check the standard run does not hold' {
        $extra = Get-CheckResultFixture -Id 'tpm-bitlocker' -Category 'security' -Severity 'OK' -Summary 'not in this run'
        $path = Write-ElevatedResultFixture -Results @($extra)

        $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

        @($import.Results.id) | Should -Be @('disk-space', 'services')
        @($import.ElevatedChecks).Count | Should -Be 0
    }

    Context 'a refused file' {
        It 'gives one UNKNOWN elevated-pass note for <Case> and changes no result' -ForEach @(
            @{ Case = 'a wrong format'; Format = 'elevated-result/2'; OffsetSeconds = 5; Bad = $false; Reason = '*format*' }
            @{ Case = 'a ran_at before the file was created'; Format = 'elevated-result/1'; OffsetSeconds = -5; Bad = $false; Reason = '*ran_at*' }
            @{ Case = 'a result failing Assert-CheckResult'; Format = 'elevated-result/1'; OffsetSeconds = 5; Bad = $true; Reason = '*severity*' }
        ) {
            $results = @($script:elevatedDisk)
            if ($Bad) {
                $results = @(Get-CheckResultFixture -Id 'disk-space' -Category 'storage' -Severity 'SEVERE' -Summary 'bad')
            }
            $path = Write-ElevatedResultFixture -Results $results -Format $Format -OffsetSeconds $OffsetSeconds

            $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

            $notes = @(Get-Note $import)
            $notes.Count | Should -Be 1
            $notes[0].severity | Should -BeExactly 'UNKNOWN'
            $notes[0].summary | Should -BeLike $Reason
            { Assert-CheckResult $notes[0] } | Should -Not -Throw
            $import.Rejected | Should -BeLike $Reason
            ($import.Results | Where-Object id -EQ 'disk-space').summary | Should -BeExactly 'standard reading'
            @($import.Results).Count | Should -Be 3
            @($import.ElevatedChecks).Count | Should -Be 0
        }

        It 'refuses an empty file, the state an elevated pass that never ran leaves' {
            $path = Join-Path $TestDrive "$([guid]::NewGuid()).json"
            [System.IO.File]::Create($path).Dispose()

            $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

            @(Get-Note $import).Count | Should -Be 1
            $import.Rejected | Should -BeLike '*empty*'
        }

        It 'refuses a missing file' {
            $import = Import-ElevatedResult -Path (Join-Path $TestDrive 'missing.json') -CheckResults $script:standard

            @(Get-Note $import).Count | Should -Be 1
            $import.Rejected | Should -BeLike '*does not exist*'
        }

        It 'refuses a check id that appears twice' {
            $path = Write-ElevatedResultFixture -Results @($script:elevatedDisk, $script:elevatedDisk)

            $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

            @(Get-Note $import).Count | Should -Be 1
            $import.Rejected | Should -BeLike '*twice*'
        }
    }
}
