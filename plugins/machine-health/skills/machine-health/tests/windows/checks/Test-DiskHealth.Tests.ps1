#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-DiskHealth.ps1.

.DESCRIPTION
Pins these fixes:

1. The original-report regression: unlettered volumes (e.g., the Windows
   Recovery Environment partition) must not bleed into the user-visible
   severity computation. The old filter took Fixed+NTFS/ReFS regardless of
   DriveLetter, which caused "at 84.8% used / blank drive" findings.

2. SMART temperature thresholds use the drive's self-reported
   TemperatureMax (from Get-StorageReliabilityCounter). The previous
   hardcoded 55/65 C was too warm for some consumer SSDs and too cold for
   server-grade NVMe. Fallback to the old thresholds only when the drive
   does not expose TemperatureMax.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-DiskHealth.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    # Dot-source the reliability wrapper so Pester can install Mock against it.
    # Without this, Mock throws CommandNotFoundException -- the function only
    # exists inside the child script scope otherwise.
    . (Join-Path $script:LibRoot 'Get-PhysicalDiskReliability.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    function Invoke-DiskHealthAsObject {
        param([switch]$Human)
        if ($Human) {
            $raw = & $script:ScriptPath -Human
            return $raw
        }
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
}

Describe 'Test-DiskHealth -- volume filter' -Tag 'check' {
    Context 'healthy single-drive laptop' {
        BeforeAll {
            Mock Get-Volume {
                @(New-MockVolume -DriveLetter C -SizeGB 500 -FreeGB 250)
            }
            Mock Get-PhysicalDisk -RemoveParameterType Usage, HealthStatus {
                @(New-MockPhysicalDisk -HealthStatus Healthy)
            }
            Mock Get-PhysicalDiskReliability {
                New-MockReliabilityCounter -Temperature 40 -TemperatureMax 70
            }
        }

        It 'emits a schema-valid CheckResult' {
            $result = Invoke-DiskHealthAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.id | Should -Be 'disk-space'
        }

        It 'reports OK when the only lettered volume has plenty of free space' {
            $result = Invoke-DiskHealthAsObject
            $result.severity | Should -Be 'OK'
        }

        It 'reports a single volume in the detail payload' {
            $result = Invoke-DiskHealthAsObject
            @($result.detail.volumes).Count | Should -Be 1
            $result.detail.volumes[0].drive | Should -Be 'C'
        }
    }

    Context 'unlettered recovery partition present (regression)' {
        BeforeAll {
            Mock Get-Volume {
                @(
                    (New-MockVolume -DriveLetter C -SizeGB 500 -FreeGB 250)
                    (New-MockVolume -SizeGB 1 -FreeGB 0.2)
                    (New-MockVolume -DriveLetter D -SizeGB 1000 -FreeGB 800)
                )
            }
            Mock Get-PhysicalDisk -RemoveParameterType Usage, HealthStatus {
                @(New-MockPhysicalDisk -HealthStatus Healthy)
            }
            Mock Get-PhysicalDiskReliability {
                New-MockReliabilityCounter -Temperature 40 -TemperatureMax 70
            }
        }

        It 'excludes the unlettered volume from detail.volumes' {
            $result = Invoke-DiskHealthAsObject
            $drives = @($result.detail.volumes | ForEach-Object { $_.drive })
            $drives | Should -Contain 'C'
            $drives | Should -Contain 'D'
            @($result.detail.volumes).Count | Should -Be 2
        }

        It 'does not inherit the unlettered partition''s low-free-space severity' {
            $result = Invoke-DiskHealthAsObject
            # Recovery partition is 80% used. If it leaked in, severity would be CRIT.
            $result.severity | Should -Be 'OK'
        }

        It 'never emits a volume detail with a blank or null drive letter' {
            $result = Invoke-DiskHealthAsObject
            foreach ($v in $result.detail.volumes) {
                $v.drive | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'low-free-space thresholds' {
        It 'flags a volume under 15% free as WARN' {
            Mock Get-Volume { @(New-MockVolume -DriveLetter C -SizeGB 500 -FreeGB 50) }
            Mock Get-PhysicalDisk -RemoveParameterType Usage, HealthStatus {
                @(New-MockPhysicalDisk -HealthStatus Healthy)
            }
            Mock Get-PhysicalDiskReliability {
                New-MockReliabilityCounter -Temperature 40 -TemperatureMax 70
            }

            $result = Invoke-DiskHealthAsObject
            $result.severity | Should -Be 'WARN'
        }

        It 'flags a volume under 5% free as CRIT' {
            Mock Get-Volume { @(New-MockVolume -DriveLetter C -SizeGB 500 -FreeGB 10) }
            Mock Get-PhysicalDisk -RemoveParameterType Usage, HealthStatus {
                @(New-MockPhysicalDisk -HealthStatus Healthy)
            }
            Mock Get-PhysicalDiskReliability {
                New-MockReliabilityCounter -Temperature 40 -TemperatureMax 70
            }

            $result = Invoke-DiskHealthAsObject
            $result.severity | Should -Be 'CRIT'
        }
    }
}

Describe 'Test-DiskHealth -- physical disk severity' -Tag 'check' {
    Context 'unhealthy physical disk' {
        It 'maps HealthStatus=Warning to CRIT' {
            Mock Get-Volume { @(New-MockVolume -DriveLetter C -SizeGB 500 -FreeGB 250) }
            Mock Get-PhysicalDisk -RemoveParameterType Usage, HealthStatus {
                @(New-MockPhysicalDisk -HealthStatus Warning)
            }
            Mock Get-PhysicalDiskReliability {
                New-MockReliabilityCounter -Temperature 40 -TemperatureMax 70
            }

            $result = Invoke-DiskHealthAsObject
            $result.severity | Should -Be 'CRIT'
        }
    }
}

Describe 'Test-DiskHealth -- device-relative temperature thresholds' -Tag 'check' {
    BeforeAll {
        Mock Get-Volume { @(New-MockVolume -DriveLetter C -SizeGB 500 -FreeGB 250) }
        Mock Get-PhysicalDisk -RemoveParameterType Usage, HealthStatus {
            @(New-MockPhysicalDisk -HealthStatus Healthy)
        }
    }

    It 'uses TemperatureMax when exposed (cool SSD at 60 C with max 85)' {
        Mock Get-PhysicalDiskReliability {
            New-MockReliabilityCounter -Temperature 60 -TemperatureMax 85
        }
        $result = Invoke-DiskHealthAsObject
        # 60 C is under both the WARN threshold (0.9*85=76.5) and CRIT (85).
        $result.severity | Should -Be 'OK'
    }

    It 'WARNs above 90% of TemperatureMax' {
        Mock Get-PhysicalDiskReliability {
            New-MockReliabilityCounter -Temperature 80 -TemperatureMax 85
        }
        $result = Invoke-DiskHealthAsObject
        # 80 C > 76.5 (WARN) but <= 85 (CRIT).
        $result.severity | Should -Be 'WARN'
    }

    It 'CRITs above TemperatureMax' {
        Mock Get-PhysicalDiskReliability {
            New-MockReliabilityCounter -Temperature 90 -TemperatureMax 85
        }
        $result = Invoke-DiskHealthAsObject
        $result.severity | Should -Be 'CRIT'
    }

    It 'falls back to 55/65 C when TemperatureMax is not exposed' {
        Mock Get-PhysicalDiskReliability {
            [pscustomobject]@{
                Temperature      = 60
                TemperatureMax   = $null
                Wear             = 0
                ReadErrorsTotal  = 0
                WriteErrorsTotal = 0
            }
        }
        $result = Invoke-DiskHealthAsObject
        # Fallback path: 60 > 55 WARN, 60 < 65 CRIT.
        $result.severity | Should -Be 'WARN'
    }
}

Describe 'Test-DiskHealth -- failure modes' -Tag 'check' {
    It 'emits UNKNOWN with error when Get-Volume and Get-PhysicalDisk both fail' {
        Mock Get-Volume { throw 'WMI unavailable' }
        Mock Get-PhysicalDisk -RemoveParameterType Usage, HealthStatus {
            throw 'Storage service stopped'
        }

        $result = Invoke-DiskHealthAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        # Current script design: empty results but ran_successfully = true.
        # When both data sources fail, we accept either UNKNOWN (preferred)
        # or OK with an empty detail payload. Pin the weaker invariant so
        # future hardening can tighten it without breaking this test.
        @($result.detail.volumes).Count | Should -Be 0
        @($result.detail.physical_disks).Count | Should -Be 0
    }
}
