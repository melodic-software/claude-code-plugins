#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Import-ElevatedResult.ps1. The acceptance rules
(format 'elevated-result/1', elevated true, the importing user's SID, ran_at
after the file's creation time, Assert-CheckResult, elevation-matrix ids only)
and the elevated-pass notes come from reference/windows/elevation-matrix.md,
"How to run elevated".
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Import-ElevatedResult.ps1'
    $script:Sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

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
            [int] $OffsetSeconds = 5,
            $Elevated = $true,
            [string] $UserSid = $script:Sid,
            [string[]] $Log = @()
        )
        $path = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        [System.IO.File]::Create($path).Dispose()
        $created = [System.IO.File]::GetCreationTimeUtc($path)
        $doc = [ordered]@{
            format   = $Format
            ran_at   = $created.AddSeconds($OffsetSeconds).ToString('o')
            elevated = $Elevated
            user_sid = $UserSid
            results  = @($Results)
            log      = @($Log)
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

    It 'appends an elevated result for a matrix check the standard run did not dispatch and lists it' {
        $extra = Get-CheckResultFixture -Id 'tpm-bitlocker' -Category 'security' -Severity 'OK' -Summary 'not in this run'
        $path = Write-ElevatedResultFixture -Results @($extra, $script:elevatedDisk)

        $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

        $import.Rejected | Should -BeNullOrEmpty
        @($import.Results.id) | Should -Be @('disk-space', 'services', 'tpm-bitlocker')
        ($import.Results | Where-Object id -EQ 'tpm-bitlocker').summary | Should -BeExactly 'not in this run'
        @($import.ElevatedChecks) | Should -Be @('disk-space', 'tpm-bitlocker')
        @(Get-Note $import).Count | Should -Be 0
    }

    It 'accepts a result written 23 hours before the importing run started' {
        $path = Write-ElevatedResultFixture -Results @($script:elevatedDisk)
        $runStart = [System.IO.File]::GetCreationTimeUtc($path).AddHours(23)

        $import = Import-ElevatedResult -Path $path -CheckResults $script:standard -RunStart $runStart

        $import.Rejected | Should -BeNullOrEmpty
        @($import.ElevatedChecks) | Should -Be @('disk-space')
    }

    It 'drops a result for a check with no elevation-matrix row and counts it in one INFO note' {
        # services has no Get-ElevationMatrix row.
        $elevatedServices = Get-CheckResultFixture -Id 'services' -Category 'services' -Severity 'CRIT' -Summary 'from the file'
        $path = Write-ElevatedResultFixture -Results @($script:elevatedDisk, $elevatedServices)

        $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

        $import.Rejected | Should -BeNullOrEmpty
        ($import.Results | Where-Object id -EQ 'services').summary | Should -BeExactly 'services fine'
        @($import.ElevatedChecks) | Should -Be @('disk-space')
        $notes = @(Get-Note $import)
        $notes.Count | Should -Be 1
        $notes[0].severity | Should -BeExactly 'INFO'
        $notes[0].summary | Should -BeLike '*dropped 1 result*'
        @($notes[0].detail.dropped_check_ids) | Should -Be @('services')
        { Assert-CheckResult $notes[0] } | Should -Not -Throw
    }

    It 'returns the log lines on one line each, at most 200' {
        $lines = @("first`r`nsecond") + @(1..250 | ForEach-Object { "line $_" })
        $path = Write-ElevatedResultFixture -Results @($script:elevatedDisk) -Log $lines

        $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

        @($import.Log).Count | Should -Be 200
        $import.Log[0] | Should -BeExactly 'first  second'
        $import.Log[199] | Should -BeExactly 'line 199'
    }

    Context 'a refused file' {
        It 'gives one UNKNOWN elevated-pass note for <Case> and changes no result' -ForEach @(
            @{ Case = 'a wrong format'; Format = 'elevated-result/2'; OffsetSeconds = 5; Elevated = $true; Sid = 'current'; Bad = $false; Reason = '*format*' }
            @{ Case = 'a ran_at before the file was created'; Format = 'elevated-result/1'; OffsetSeconds = -5; Elevated = $true; Sid = 'current'; Bad = $false; Reason = '*ran_at*' }
            @{ Case = 'a result failing Assert-CheckResult'; Format = 'elevated-result/1'; OffsetSeconds = 5; Elevated = $true; Sid = 'current'; Bad = $true; Reason = '*severity*' }
            @{ Case = 'elevated false'; Format = 'elevated-result/1'; OffsetSeconds = 5; Elevated = $false; Sid = 'current'; Bad = $false; Reason = '*elevated is not true*' }
            @{ Case = 'elevated as the string true'; Format = 'elevated-result/1'; OffsetSeconds = 5; Elevated = 'true'; Sid = 'current'; Bad = $false; Reason = '*elevated is not true*' }
            @{ Case = 'another user''s SID'; Format = 'elevated-result/1'; OffsetSeconds = 5; Elevated = $true; Sid = 'S-1-5-18'; Bad = $false; Reason = '*written by another account*describe that account*' }
        ) {
            $results = @($script:elevatedDisk)
            if ($Bad) {
                $results = @(Get-CheckResultFixture -Id 'disk-space' -Category 'storage' -Severity 'SEVERE' -Summary 'bad')
            }
            $userSid = if ($Sid -eq 'current') { $script:Sid } else { $Sid }
            $path = Write-ElevatedResultFixture -Results $results -Format $Format -OffsetSeconds $OffsetSeconds `
                -Elevated $Elevated -UserSid $userSid

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
            @($import.Log).Count | Should -Be 0
        }

        It 'refuses an empty file, the state an elevated pass that never ran leaves' {
            $path = Join-Path $TestDrive "$([guid]::NewGuid()).json"
            [System.IO.File]::Create($path).Dispose()

            $import = Import-ElevatedResult -Path $path -CheckResults $script:standard

            @(Get-Note $import).Count | Should -Be 1
            $import.Rejected | Should -BeLike '*empty*'
        }

        It 'refuses a result written more than 24 hours before the importing run started' {
            $path = Write-ElevatedResultFixture -Results @($script:elevatedDisk)
            $runStart = [System.IO.File]::GetCreationTimeUtc($path).AddHours(25)

            $import = Import-ElevatedResult -Path $path -CheckResults $script:standard -RunStart $runStart

            @(Get-Note $import).Count | Should -Be 1
            $import.Rejected | Should -BeLike '*more than 24 hours*'
            @($import.ElevatedChecks).Count | Should -Be 0
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
