#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibPath = Join-Path $script:SkillRoot 'scripts\windows\lib\Get-GpuDriverInfo.ps1'
    . $script:LibPath
}

Describe 'Get-GpuDriverInfo' -Tag 'lib' {
    BeforeEach {
        # Make nvidia-smi appear absent so every test exercises the
        # Win32_VideoController fallback path in isolation.
        Mock Get-Command {
            param($Name) if ($Name -eq 'nvidia-smi') { $null }
        }
    }

    It 'returns an empty array when no GPUs are enumerable' {
        Mock Get-CimInstance { throw 'No WMI' } -ParameterFilter {
            $ClassName -eq 'Win32_VideoController'
        }
        $result = @(Get-GpuDriverInfo)
        $result.Count | Should -Be 0
    }

    It 'maps Intel GPU from Win32_VideoController' {
        Mock Get-CimInstance {
            @([pscustomobject]@{
                    Name          = 'Intel(R) UHD Graphics 630'
                    DriverVersion = '31.0.101.2111'
                    DriverDate    = (Get-Date '2024-06-15')
                })
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
        $result = @(Get-GpuDriverInfo)
        $result.Count | Should -Be 1
        $result[0].vendor | Should -Be 'Intel'
        $result[0].source | Should -Be 'Win32_VideoController'
    }

    It 'maps AMD GPU from Win32_VideoController' {
        Mock Get-CimInstance {
            @([pscustomobject]@{
                    Name          = 'AMD Radeon RX 7900 XTX'
                    DriverVersion = '24.10.1'
                    DriverDate    = (Get-Date '2024-10-20')
                })
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
        $result = @(Get-GpuDriverInfo)
        $result[0].vendor | Should -Be 'AMD'
    }

    It 'skips NVIDIA entries from Win32_VideoController (already covered by nvidia-smi path)' {
        Mock Get-CimInstance {
            @([pscustomobject]@{
                    Name          = 'NVIDIA GeForce RTX 4090'
                    DriverVersion = '551.23'
                    DriverDate    = (Get-Date '2024-11-01')
                })
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
        $result = @(Get-GpuDriverInfo)
        $result.Count | Should -Be 0
    }
}
