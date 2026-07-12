#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Smoke tests for the Pester scaffold itself (runner, helpers, fixture paths).

.DESCRIPTION
These tests verify the test infrastructure works end-to-end before any
check-specific tests exist. If these fail, nothing else can run.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent $PSScriptRoot
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    . (Join-Path $script:TestsRoot 'helpers\Invoke-FixtureRedaction.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force
}

Describe 'Scaffold -- Assert-CheckResult' {
    Context 'valid CheckResult shapes' {
        It 'accepts a minimal OK result' {
            $r = [pscustomobject]@{
                id = 'disk-space'; category = 'storage'; os = 'windows'
                ran_at = (Get-Date).ToString('o'); severity = 'OK'
                summary = 'healthy'; detail = @{}; commands = @()
                needs_admin = $false; ran_successfully = $true; duration_ms = 10
                trend = $null; notes = $null; error = $null
            }
            Assert-CheckResult $r | Should -BeTrue
        }

        It 'accepts an UNKNOWN result with error' {
            $r = [pscustomobject]@{
                id = 'defender'; category = 'security'; os = 'windows'
                ran_at = (Get-Date).ToString('o'); severity = 'UNKNOWN'
                summary = 'Defender cmdlets unavailable.'; detail = @{}; commands = @()
                needs_admin = $false; ran_successfully = $false; duration_ms = 5
                trend = $null; notes = 'Module blocked'; error = 'Get-MpComputerStatus missing'
            }
            Assert-CheckResult $r | Should -BeTrue
        }
    }

    Context 'invalid CheckResult shapes' {
        It 'rejects a missing required field' {
            $r = [pscustomobject]@{ id = 'x'; category = 'storage' }
            { Assert-CheckResult $r } | Should -Throw -ExpectedMessage '*missing required field*'
        }

        It 'rejects an invalid severity' {
            $r = [pscustomobject]@{
                id = 'disk-space'; category = 'storage'; os = 'windows'
                ran_at = (Get-Date).ToString('o'); severity = 'BAD'
                summary = 'x'; detail = @{}; commands = @()
                needs_admin = $false; ran_successfully = $true; duration_ms = 1
                trend = $null; notes = $null; error = $null
            }
            { Assert-CheckResult $r } | Should -Throw -ExpectedMessage '*severity*not in allowed set*'
        }

        It 'rejects ran_successfully=false without UNKNOWN severity' {
            $r = [pscustomobject]@{
                id = 'defender'; category = 'security'; os = 'windows'
                ran_at = (Get-Date).ToString('o'); severity = 'OK'
                summary = 'x'; detail = @{}; commands = @()
                needs_admin = $false; ran_successfully = $false; duration_ms = 1
                trend = $null; notes = $null; error = 'x'
            }
            { Assert-CheckResult $r } | Should -Throw -ExpectedMessage '*severity must be UNKNOWN*'
        }

        It 'rejects a non-kebab-case id' {
            $r = [pscustomobject]@{
                id = 'DiskSpace'; category = 'storage'; os = 'windows'
                ran_at = (Get-Date).ToString('o'); severity = 'OK'
                summary = 'x'; detail = @{}; commands = @()
                needs_admin = $false; ran_successfully = $true; duration_ms = 1
                trend = $null; notes = $null; error = $null
            }
            { Assert-CheckResult $r } | Should -Throw -ExpectedMessage '*kebab-case*'
        }
    }
}

Describe 'Scaffold -- Mock factories' {
    It 'New-MockVolume returns expected shape' {
        $v = New-MockVolume -DriveLetter C -SizeGB 500 -FreeGB 100
        $v.DriveLetter | Should -Be 'C'
        $v.Size | Should -Be ([long](500 * 1GB))
        $v.SizeRemaining | Should -Be ([long](100 * 1GB))
        $v.FileSystem | Should -Be 'NTFS'
    }

    It 'New-MockVolume supports unlettered volumes' {
        $v = New-MockVolume
        $v.DriveLetter | Should -BeNullOrEmpty
    }

    It 'New-MockPartition respects Type validation' {
        $p = New-MockPartition -Type Recovery
        $p.Type | Should -Be 'Recovery'
    }

    It 'New-MockPhysicalDisk defaults to Healthy' {
        $d = New-MockPhysicalDisk
        $d.HealthStatus | Should -Be 'Healthy'
        $d.OperationalStatus | Should -Contain 'OK'
    }

    It 'New-MockReliabilityCounter exposes TemperatureMax for device-relative thresholds' {
        $c = New-MockReliabilityCounter -Temperature 60 -TemperatureMax 70
        $c.Temperature | Should -Be 60
        $c.TemperatureMax | Should -Be 70
    }

    It 'New-MockService supports stopped state' {
        $s = New-MockService -Name 'wuauserv' -StartType Automatic -Status Stopped
        $s.Status | Should -Be 'Stopped'
        $s.StartType | Should -Be 'Automatic'
    }

    It 'New-MockDefenderComputerStatus returns healthy defaults' {
        $m = New-MockDefenderComputerStatus
        $m.RealTimeProtectionEnabled | Should -BeTrue
        $m.AntivirusSignatureAge | Should -Be 1
    }
}

Describe 'Scaffold -- Invoke-FixtureRedaction' {
    It 'replaces username inside string values' {
        $payload = [pscustomobject]@{ Path = "C:\Users\$env:USERNAME\Documents\foo.txt" }
        $out = Invoke-FixtureRedaction -InputObject $payload
        $out.Path | Should -Not -Match ([regex]::Escape("$env:USERNAME"))
        $out.Path | Should -Match '__USERNAME__'
    }

    It 'replaces hostname inside string values' {
        $payload = [pscustomobject]@{ Server = "\\$env:COMPUTERNAME\share" }
        $out = Invoke-FixtureRedaction -InputObject $payload
        $out.Server | Should -Match '__HOSTNAME__'
    }

    It 'replaces other drive letters but preserves the subject drive' {
        $payload = [pscustomobject]@{
            Primary   = 'C:\work'
            Secondary = 'E:\backup'
        }
        $out = Invoke-FixtureRedaction -InputObject $payload -PreserveDriveLetter ([char]'C')
        $out.Primary | Should -BeExactly 'C:\work'
        $out.Secondary | Should -BeExactly '__DRIVE__:\backup'
    }

    It 'replaces MAC addresses' {
        $payload = [pscustomobject]@{ Mac = 'AA:BB:CC:DD:EE:FF' }
        $out = Invoke-FixtureRedaction -InputObject $payload
        $out.Mac | Should -BeExactly '00-00-00-00-00-00'
    }

    It 'recursively redacts nested arrays and hashtables' {
        $payload = [pscustomobject]@{
            Disks = @(
                [pscustomobject]@{ Path = "D:\Users\$env:USERNAME\cache" },
                [pscustomobject]@{ Path = 'E:\other' }
            )
        }
        $out = Invoke-FixtureRedaction -InputObject $payload -PreserveDriveLetter ([char]'D')
        $out.Disks[0].Path | Should -Match '__USERNAME__'
        $out.Disks[0].Path | Should -Match '^D:'
        $out.Disks[1].Path | Should -Match '^__DRIVE__:'
    }

    It 'preserves null values and non-string primitives' {
        $payload = [pscustomobject]@{
            Count = 42
            Nothing = $null
            Flag = $true
        }
        $out = Invoke-FixtureRedaction -InputObject $payload
        $out.Count | Should -Be 42
        $out.Nothing | Should -BeNullOrEmpty
        $out.Flag | Should -BeTrue
    }
}
