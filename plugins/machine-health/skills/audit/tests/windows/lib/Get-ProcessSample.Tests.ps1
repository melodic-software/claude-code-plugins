#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-ProcessSample.ps1. Expected values are computed
by hand from the mocked snapshots: CPU share = delta seconds / (interval x CPUs) x 100.
Counter sample shapes follow a real Get-Counter read (lowercased \\host\object\counter
paths, Status 0 for a valid sample).
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ProcessSample.ps1'

    $script:T0 = [datetime]::new(2026, 10, 21, 12, 0, 0, [DateTimeKind]::Utc)

    function New-MockProcess {
        param(
            [int] $Id, [string] $Name, $CpuSeconds, $StartTime,
            [string] $Path = $null, [long] $WorkingSet = 100MB, [long] $Private = 50MB
        )
        [pscustomobject]@{
            Id                  = $Id
            ProcessName         = $Name
            TotalProcessorTime  = ($null -eq $CpuSeconds) ? $null : [timespan]::FromSeconds($CpuSeconds)
            StartTime           = $StartTime
            Path                = $Path
            WorkingSet64        = $WorkingSet
            PrivateMemorySize64 = $Private
        }
    }

    function New-CounterSet {
        param([hashtable] $Value, [int] $Status = 0)
        $names = @{
            cpu       = '\\host\processor(_total)\% processor time'
            queue     = '\\host\system\processor queue length'
            committed = '\\host\memory\% committed bytes in use'
            available = '\\host\memory\available mbytes'
            read      = '\\host\physicaldisk(_total)\avg. disk sec/read'
            write     = '\\host\physicaldisk(_total)\avg. disk sec/write'
        }
        [pscustomobject]@{
            CounterSamples = @($Value.Keys | ForEach-Object {
                    [pscustomobject]@{ Path = $names[$_]; Status = $Status; CookedValue = $Value[$_] }
                })
        }
    }

    function Set-SampleClock {
        param([double[]] $Seconds)
        $script:Clock = [System.Collections.Queue]::new()
        foreach ($s in $Seconds) { $script:Clock.Enqueue($script:T0.AddSeconds($s)) }
    }
}

Describe 'Get-ProcessSample' -Tag 'lib' {
    BeforeEach {
        Mock Get-Date { $script:Clock.Dequeue() }
        Mock Start-Sleep { }
        Mock Get-CimInstance {
            [pscustomobject]@{ NumberOfLogicalProcessors = 4; TotalPhysicalMemory = 16GB }
        } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        $script:Snapshots = [System.Collections.Queue]::new()
        Mock Get-Process { $script:Snapshots.Dequeue() }
    }

    Context 'CPU share from two snapshots' {
        BeforeEach {
            $started = $script:T0.AddHours(-1)
            $script:Snapshots.Enqueue(@(
                    (New-MockProcess -Id 0 -Name 'Idle' -CpuSeconds 5000 -StartTime $null)
                    (New-MockProcess -Id 100 -Name 'steady' -CpuSeconds 10 -StartTime $started -Path 'C:\app\steady.exe')
                    (New-MockProcess -Id 200 -Name 'old' -CpuSeconds 100 -StartTime $started)
                    (New-MockProcess -Id 300 -Name 'locked' -CpuSeconds $null -StartTime $null)
                ))
            $script:Snapshots.Enqueue(@(
                    (New-MockProcess -Id 0 -Name 'Idle' -CpuSeconds 5050 -StartTime $null)
                    (New-MockProcess -Id 100 -Name 'steady' -CpuSeconds 13 -StartTime $started -Path 'C:\app\steady.exe')
                    (New-MockProcess -Id 200 -Name 'old' -CpuSeconds 1.2 -StartTime $script:T0.AddSeconds(5))
                    (New-MockProcess -Id 400 -Name 'fresh' -CpuSeconds 0.6 -StartTime $script:T0.AddSeconds(3))
                    (New-MockProcess -Id 300 -Name 'locked' -CpuSeconds $null -StartTime $null)
                    (New-MockProcess -Id 4 -Name 'System' -CpuSeconds $null -StartTime $null)
                ))
            Mock Get-Counter { }
            Set-SampleClock -Seconds 0, 15, 15
            $script:Sample = Get-ProcessSample -SampleSeconds 15
            $script:ById = @{}
            foreach ($p in $script:Sample.Processes) { $script:ById[$p.Id] = $p }
        }

        It 'divides a 3 s delta over 15 s on 4 CPUs into 5 percent' {
            $script:ById[100].CpuPct | Should -Be 5.0
        }

        It 'counts all processor time of a process that started inside the window' {
            $script:ById[400].CpuPct | Should -Be 1.0
        }

        It 'treats a reused process id with a new start time as a new process' {
            $script:ById[200].CpuPct | Should -Be 2.0
        }

        It 'leaves CpuPct null when processor time is unreadable' {
            $script:ById[300].CpuPct | Should -BeNullOrEmpty
        }

        It 'drops the Idle pseudo-process' {
            $script:ById.ContainsKey(0) | Should -BeFalse
        }

        It 'reports the measured interval and the logical CPU count' {
            $script:Sample.IntervalSeconds | Should -Be 15
            $script:Sample.LogicalCpus | Should -Be 4
        }

        It 'labels a readable path ok, System absent and an unreadable one denied' {
            $script:ById[100].PathState | Should -Be 'ok'
            $script:ById[100].Path | Should -Be 'C:\app\steady.exe'
            $script:ById[4].PathState | Should -Be 'absent'
            $script:ById[300].PathState | Should -Be 'denied'
            $script:ById[300].Path | Should -BeNullOrEmpty
        }

        It 'carries working set and private bytes as numbers' {
            $script:ById[100].WorkingSetBytes | Should -Be 100MB
            $script:ById[100].PrivateBytes | Should -Be 50MB
        }
    }

    Context 'system counters' {
        BeforeEach {
            $script:Snapshots.Enqueue(@())
            $script:Snapshots.Enqueue(@())
        }

        It 'averages each counter and takes the median of the slower disk direction in ms' {
            Mock Get-Counter {
                (New-CounterSet -Value @{ cpu = 20; queue = 2; committed = 50; available = 1000; read = 0.010; write = 0.020 })
                (New-CounterSet -Value @{ cpu = 40; queue = 4; committed = 60; available = 3000; read = 0.030; write = 0.005 })
                (New-CounterSet -Value @{ cpu = 90; queue = 9; committed = 90; available = 9000; read = 9; write = 9 } -Status 1)
            }
            Set-SampleClock -Seconds 0, 15, 15
            $sample = Get-ProcessSample -SampleSeconds 15
            $sample.Counters.CpuTotalPct | Should -Be 30
            $sample.Counters.ProcessorQueueLength | Should -Be 3
            $sample.Counters.CommittedPct | Should -Be 55
            $sample.Counters.AvailableMb | Should -Be 2000
            $sample.Counters.TotalPhysicalMb | Should -Be 16384
            $sample.Counters.DiskLatencyMs | Should -Be 25
            $sample.ReadState | Should -Be 'ok'
        }

        It 'asks Get-Counter for one sample per second of the window' {
            Mock Get-Counter { }
            Set-SampleClock -Seconds 0, 60, 60
            $null = Get-ProcessSample -SampleSeconds 60
            Should -Invoke Get-Counter -Times 1 -ParameterFilter { $SampleInterval -eq 1 -and $MaxSamples -eq 60 }
        }

        It 'reads error and still waits out the window when the counter read returns nothing' {
            Mock Get-Counter { }
            Set-SampleClock -Seconds 0, 2, 15
            $sample = Get-ProcessSample -SampleSeconds 15
            $sample.ReadState | Should -Be 'error'
            $sample.Counters.CpuTotalPct | Should -BeNullOrEmpty
            Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Milliseconds -eq 13000 }
        }

        It 'reads error when one counter has no valid sample' {
            Mock Get-Counter {
                New-CounterSet -Value @{ cpu = 20; queue = 2; committed = 50; available = 1000; read = 0.010 }
            }
            Set-SampleClock -Seconds 0, 15, 15
            $sample = Get-ProcessSample -SampleSeconds 15
            $sample.Counters.DiskLatencyMs | Should -BeNullOrEmpty
            $sample.ReadState | Should -Be 'error'
        }
    }
}
