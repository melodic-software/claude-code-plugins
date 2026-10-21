#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-TopProcesses.ps1 with Get-ProcessSample mocked.
Band edges come from Microsoft Learn's Windows Server performance pages (research table:
% Processor Time warning 50-80, critical 80-100; queue length 2 or more per processor with
high CPU; available memory warning under 10%, critical under 1% or 500 MB; committed warning
60-80, critical 80-100; disk latency warning over 25 ms, critical over 50 ms, sustained over
about a minute). Learn's warning band reads INFO and its critical band WARN.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-TopProcesses' `
        -LibScript 'Get-ProcessSample.ps1'

    function New-Sample {
        param(
            $Cpu = 10, $Queue = 0, $Committed = 30, $Available = 8000, $Total = 16000, $Disk = 5,
            [string] $ReadState = 'ok', [object[]] $Processes = @()
        )
        [pscustomobject]@{
            IntervalSeconds = 15
            LogicalCpus     = 4
            Processes       = $Processes
            Counters        = [pscustomobject]@{
                CpuTotalPct = $Cpu; ProcessorQueueLength = $Queue; CommittedPct = $Committed
                AvailableMb = $Available; TotalPhysicalMb = $Total; DiskLatencyMs = $Disk
            }
            ReadState       = $ReadState
        }
    }

    function Invoke-TopProcessCheck {
        param([int] $SampleSeconds = 0)
        $raw = $SampleSeconds ? (& $script:ScriptPath -SampleSeconds $SampleSeconds) : (& $script:ScriptPath)
        return ConvertFrom-CheckOutput $raw
    }
}

Describe 'Test-TopProcesses' -Tag 'check' {
    Context 'a quiet machine on the default window' {
        BeforeAll {
            Mock Get-ProcessSample { New-Sample }
            $script:Result = Invoke-TopProcessCheck
        }

        It 'is OK and passes the CheckResult schema' {
            $script:Result.severity | Should -Be 'OK'
            { Assert-CheckResult $script:Result } | Should -Not -Throw
        }

        It 'samples for 15 seconds by default and reports that window' {
            Should -Invoke Get-ProcessSample -Times 1 -Scope Context -ParameterFilter { $SampleSeconds -eq 15 }
            $script:Result.detail.sample_seconds | Should -Be 15
        }

        It 'labels the thresholds as Windows Server guidance' {
            $script:Result.detail.thresholds_label | Should -Be 'Windows Server guidance (Microsoft Learn)'
        }

        It 'says disk latency was not sustained-tested below a minute' {
            $script:Result.detail.disk_latency_sustained | Should -BeFalse
            $script:Result.summary | Should -Match 'not sustained-tested'
        }

        It 'reports queue per CPU and available percent' {
            $script:Result.detail.processor_queue_per_cpu | Should -Be 0
            $script:Result.detail.available_pct | Should -Be 50
        }
    }

    Context 'severity bands' {
        It 'reads CPU at <Cpu>% with queue <Queue> on 4 CPUs as <Expected>' -ForEach @(
            @{ Cpu = 85; Queue = 0; Expected = 'WARN' }
            @{ Cpu = 60; Queue = 8; Expected = 'WARN' }
            @{ Cpu = 60; Queue = 4; Expected = 'INFO' }
            @{ Cpu = 49; Queue = 40; Expected = 'OK' }
        ) {
            Mock Get-ProcessSample { New-Sample -Cpu $Cpu -Queue $Queue }
            (Invoke-TopProcessCheck).severity | Should -Be $Expected
        }

        It 'reads <Available> MB available of 16000 as <Expected>' -ForEach @(
            @{ Available = 400; Expected = 'WARN' }
            @{ Available = 1200; Expected = 'INFO' }
            @{ Available = 1700; Expected = 'OK' }
        ) {
            Mock Get-ProcessSample { New-Sample -Available $Available }
            (Invoke-TopProcessCheck).severity | Should -Be $Expected
        }

        It 'reads <Committed>% committed as <Expected>' -ForEach @(
            @{ Committed = 85; Expected = 'WARN' }
            @{ Committed = 65; Expected = 'INFO' }
        ) {
            Mock Get-ProcessSample { New-Sample -Committed $Committed }
            (Invoke-TopProcessCheck).severity | Should -Be $Expected
        }

        It 'ignores 60 ms disk latency on a 15 s window' {
            Mock Get-ProcessSample { New-Sample -Disk 60 }
            (Invoke-TopProcessCheck).severity | Should -Be 'OK'
        }

        It 'grades disk latency on a 60 s window: <Disk> ms is <Expected>' -ForEach @(
            @{ Disk = 60; Expected = 'WARN' }
            @{ Disk = 30; Expected = 'INFO' }
            @{ Disk = 20; Expected = 'OK' }
        ) {
            Mock Get-ProcessSample { New-Sample -Disk $Disk }
            $result = Invoke-TopProcessCheck -SampleSeconds 60
            $result.severity | Should -Be $Expected
            $result.detail.disk_latency_sustained | Should -BeTrue
            $result.detail.sample_seconds | Should -Be 60
            Should -Invoke Get-ProcessSample -Times 1 -ParameterFilter { $SampleSeconds -eq 60 }
        }
    }

    Context 'counter read failure' {
        It 'is UNKNOWN, never OK, when the counters could not be read' {
            Mock Get-ProcessSample { New-Sample -Cpu $null -Queue $null -Committed $null -Available $null -Disk $null -ReadState 'error' }
            $result = Invoke-TopProcessCheck
            $result.severity | Should -Be 'UNKNOWN'
            $result.detail.counters_state | Should -Be 'error'
        }

        It 'keeps a WARN reading from the counters that did read' {
            Mock Get-ProcessSample { New-Sample -Cpu 85 -Disk $null -ReadState 'error' }
            (Invoke-TopProcessCheck).severity | Should -Be 'WARN'
        }
    }

    Context 'process items' {
        BeforeAll {
            $processes = foreach ($i in 1..12) {
                [pscustomobject]@{
                    Name = "p$i"; Id = 1000 + $i; CpuPct = [double](13 - $i); WorkingSetBytes = 2MB * $i
                    PrivateBytes = 1MB * $i; Path = $null; PathState = 'denied'
                }
            }
            Mock Get-ProcessSample { New-Sample -Processes $processes }
            $script:Result = Invoke-TopProcessCheck
        }

        It 'lists the top 10 by CPU and the top 10 by private bytes once each' {
            $script:Result.detail.items_count | Should -Be 12
            @($script:Result.detail.items.name | Sort-Object -Unique).Count | Should -Be 12
        }

        It 'puts the busiest process first with its share and memory in MB' {
            $first = $script:Result.detail.items[0]
            $first.name | Should -Be 'p1'
            $first.cpu_pct | Should -Be 12
            $first.private_mb | Should -Be 1
            $first.working_set_mb | Should -Be 2
            $first.path_state | Should -Be 'denied'
        }

        It 'never raises severity or mutes a listed process' {
            $script:Result.severity | Should -Be 'OK'
            $script:Result.detail.muted_count | Should -Be 0
            @($script:Result.detail.items | Where-Object muted).Count | Should -Be 0
        }
    }
}
