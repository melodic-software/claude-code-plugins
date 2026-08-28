#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibPath = Join-Path $script:SkillRoot 'scripts\windows\lib\Get-GpuDriverInfo.ps1'
    . $script:LibPath

    # A shadowing FUNCTION, not a Pester Mock: nvidia-smi is an Application, so
    # it cannot be mocked on a machine that does not have it installed (most CI
    # runners), and argument capture through an Application mock is unreliable
    # where it is installed. PowerShell resolves functions ahead of
    # applications, so this intercepts the lib's `& nvidia-smi` either way.
    #
    # A function does not set $LASTEXITCODE, and the lib gates on it, so the
    # stub sets it explicitly rather than inheriting whatever stale value the
    # caller's scope happens to hold.
    function nvidia-smi {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '',
            Justification = 'Deliberately shadows the nvidia-smi executable under test.')]
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Arguments)
        # Flattened through the pipeline so a nested array — which is what
        # PowerShell's argument-mode comma operator builds, and what a native
        # command would spread into separate argv entries — is captured the way
        # nvidia-smi would have received it, rather than as one joined string.
        $global:NvidiaSmiCapturedArgs = @($Arguments | ForEach-Object { $_ })
        $global:LASTEXITCODE = 0
        $global:NvidiaSmiStdout
    }
}

Describe 'Get-GpuDriverInfo' -Tag 'lib' {
    Context 'Win32_VideoController fallback' {
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

    Context 'nvidia-smi invocation' {
        BeforeEach {
            $global:NvidiaSmiCapturedArgs = $null
            $global:NvidiaSmiStdout = 'NVIDIA GeForce RTX 4090, 551.23'
            # Truthy: the lib only tests whether the command resolved. Faked so
            # the branch is reachable on hosts without the NVIDIA toolkit.
            Mock Get-Command { [pscustomobject]@{ Name = 'nvidia-smi' } } `
                -ParameterFilter { $Name -eq 'nvidia-smi' }
            Mock Get-CimInstance { @() } -ParameterFilter {
                $ClassName -eq 'Win32_VideoController'
            }
        }

        AfterEach {
            Remove-Variable -Name NvidiaSmiCapturedArgs, NvidiaSmiStdout `
                -Scope Global -ErrorAction SilentlyContinue
        }

        It 'passes --query-gpu and --format as two intact arguments' {
            # #3370: the invocation was written with a space after each comma
            # (`--query-gpu=name, driver_version`). PowerShell parses that in
            # argument mode as an ARRAY, which flattens into four separate
            # native arguments, so nvidia-smi rejected the flags and the NVIDIA
            # branch returned nothing on real hardware. Asserting on the arg
            # shape is the only discriminating check here: the stub owns both
            # the exit code and stdout.
            $null = Get-GpuDriverInfo

            $captured = @($global:NvidiaSmiCapturedArgs)
            $captured.Count | Should -Be 2
            $captured[0] | Should -BeExactly '--query-gpu=name,driver_version'
            $captured[1] | Should -BeExactly '--format=csv,noheader'
        }

        It 'maps the nvidia-smi CSV row onto an NVIDIA record' {
            $result = @(Get-GpuDriverInfo)
            $result.Count | Should -Be 1
            $result[0].vendor | Should -Be 'NVIDIA'
            $result[0].model | Should -Be 'NVIDIA GeForce RTX 4090'
            $result[0].driver_version | Should -Be '551.23'
            $result[0].source | Should -Be 'nvidia-smi'
        }
    }
}
