#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-GpuDriverInfo.ps1'

    # Win32_VideoController is a Windows cmdlet. A function of the same name lets
    # Pester mock it on a host that does not ship the Cim cmdlets.
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSAvoidOverwritingBuiltInCmdlets', '',
                Justification = 'Defined only when the Cim cmdlets are absent so Pester can mock the call.')]
            param([string] $ClassName)
            throw "Get-CimInstance is not available ($ClassName)"
        }
    }

    function New-NativeResult {
        param(
            [string] $Status = 'Ok',
            [string] $Output = ''
        )
        $source = if ($Status -eq 'Absent') { 'absent' } else { 'nvidia-smi' }
        $exitCode = switch ($Status) {
            'Ok' { 0 }
            'Absent' { $null }
            'NonZero' { 2 }
            default { $null }
        }
        [pscustomobject]@{
            status    = $Status
            source    = $source
            exit_code = $exitCode
            output    = $Output
            error     = $null
        }
    }
}

Describe 'Get-GpuDriverInfo' -Tag 'lib' {
    Context 'Win32_VideoController fallback' {
        BeforeEach {
            Mock Invoke-NativeCommand { New-NativeResult -Status 'Absent' } -ParameterFilter {
                $Name -eq 'nvidia-smi'
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

    Context 'nvidia-smi invocation' {
        BeforeEach {
            Mock Invoke-NativeCommand {
                New-NativeResult -Output 'NVIDIA GeForce RTX 4090, 551.23'
            } -ParameterFilter { $Name -eq 'nvidia-smi' }
            Mock Get-CimInstance { @() } -ParameterFilter {
                $ClassName -eq 'Win32_VideoController'
            }
        }

        It 'passes --query-gpu and --format as two intact arguments' {
            # #3370: one comma-bearing flag must stay one argv entry.
            $null = Get-GpuDriverInfo

            Should -Invoke Invoke-NativeCommand -Times 1 -ParameterFilter {
                $Name -eq 'nvidia-smi' -and
                @($ArgumentList).Count -eq 2 -and
                @($ArgumentList)[0] -eq '--query-gpu=name,driver_version' -and
                @($ArgumentList)[1] -eq '--format=csv,noheader'
            }
        }

        It 'maps the nvidia-smi CSV row onto an NVIDIA record' {
            $result = @(Get-GpuDriverInfo)
            $result.Count | Should -Be 1
            $result[0].vendor | Should -Be 'NVIDIA'
            $result[0].model | Should -Be 'NVIDIA GeForce RTX 4090'
            $result[0].driver_version | Should -Be '551.23'
            $result[0].source | Should -Be 'nvidia-smi'
        }

        It 'takes the WMI fallback when nvidia-smi exits non-zero' {
            Mock Invoke-NativeCommand { New-NativeResult -Status 'NonZero' -Output 'ignored' } -ParameterFilter {
                $Name -eq 'nvidia-smi'
            }
            Mock Get-CimInstance {
                @([pscustomobject]@{
                        Name          = 'Intel(R) UHD Graphics 630'
                        DriverVersion = '31.0.101.2111'
                        DriverDate    = (Get-Date '2024-06-15')
                    })
            } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }

            $result = @(Get-GpuDriverInfo)
            $result.Count | Should -Be 1
            $result[0].source | Should -Be 'Win32_VideoController'
        }
    }
}
