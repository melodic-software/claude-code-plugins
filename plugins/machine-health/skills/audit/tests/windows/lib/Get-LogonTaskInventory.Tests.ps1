#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-LogonTaskInventory.ps1'

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Get-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSAvoidOverwritingBuiltInCmdlets', '',
                Justification = 'Defined only when the ScheduledTasks module is absent so Pester can mock the call.')]
            param()
            throw 'Get-ScheduledTask is not available'
        }
    }

    function New-Trigger {
        param([string] $Class)
        [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = $Class } }
    }

    function New-Task {
        param([string] $Name, [object[]] $Triggers, [object[]] $Actions, [string] $State = 'Ready')
        [pscustomobject]@{
            TaskPath = '\Vendor\'
            TaskName = $Name
            Triggers = $Triggers
            Actions  = $Actions
            State    = $State
        }
    }
}

Describe 'Get-LogonTaskInventory' -Tag 'lib' {
    It 'keeps only tasks with a logon trigger and joins each action into the command' {
        Mock Test-IsElevated { $true }
        Mock Get-ScheduledTask {
            New-Task -Name 'AtLogon' -Triggers @(
                (New-Trigger 'MSFT_TaskDailyTrigger'), (New-Trigger 'MSFT_TaskLogonTrigger')
            ) -Actions @(
                [pscustomobject]@{ Execute = 'X:\Apps\sync.exe'; Arguments = '--quiet' }
                [pscustomobject]@{ ClassId = '{00000000-0000-0000-0000-000000000001}' }
            )
            New-Task -Name 'Daily' -Triggers @(New-Trigger 'MSFT_TaskDailyTrigger') -Actions @(
                [pscustomobject]@{ Execute = 'X:\Apps\daily.exe'; Arguments = $null }
            )
            New-Task -Name 'NoTrigger' -Triggers @() -Actions @()
        }

        $read = Get-LogonTaskInventory

        $read.ReadState | Should -Be 'ok'
        $read.Complete | Should -BeTrue
        @($read.Tasks).Count | Should -Be 1
        $read.Tasks[0].TaskPath | Should -Be '\Vendor\'
        $read.Tasks[0].TaskName | Should -Be 'AtLogon'
        $read.Tasks[0].Command | Should -Be 'X:\Apps\sync.exe --quiet; COM handler {00000000-0000-0000-0000-000000000001}'
        $read.Tasks[0].Enabled | Should -BeTrue
    }

    It 'marks a disabled logon task and reports the list partial without elevation' {
        Mock Test-IsElevated { $false }
        Mock Get-ScheduledTask {
            New-Task -Name 'Off' -State 'Disabled' -Triggers @(New-Trigger 'MSFT_TaskLogonTrigger') -Actions @(
                [pscustomobject]@{ Execute = 'off.exe'; Arguments = '' }
            )
        }

        $read = Get-LogonTaskInventory

        $read.Complete | Should -BeFalse
        $read.Tasks[0].Enabled | Should -BeFalse
        $read.Tasks[0].Command | Should -Be 'off.exe'
    }

    It 'reports error with no tasks when the task store cannot be read' {
        Mock Test-IsElevated { $false }
        Mock Get-ScheduledTask { throw [System.Runtime.InteropServices.COMException]::new('unavailable') }

        $read = Get-LogonTaskInventory

        $read.ReadState | Should -Be 'error'
        @($read.Tasks).Count | Should -Be 0
    }
}
