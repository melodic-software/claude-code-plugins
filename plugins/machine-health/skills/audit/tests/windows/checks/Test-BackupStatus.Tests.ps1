#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-BackupStatus.ps1 with Get-BackupSignal mocked.
The severity rule is the plan's: WARN when no source is present, UNKNOWN when any
source needs admin. The deprecation sentence is quoted from the contract.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-BackupStatus' `
        -AsObject 'Invoke-BackupStatus' -LibScript 'Get-BackupSignal.ps1', 'Test-IsElevated.ps1'

    $script:Deprecation = 'System Image Backup has been deprecated since Windows 10 version 1709.'

    function New-Source {
        param([string] $Source, [string] $State, $Count = $null)
        [pscustomobject]@{
            Source = $Source; State = $State; LastSuccess = $null; LastResultEvent = $null
            Signal = 'cim'; Basis = 'label'; Count = $Count
        }
    }

    function New-SourceSet {
        param([hashtable] $State, [hashtable] $Count = @{})
        foreach ($name in 'system-image', 'restore-points', 'file-history', 'windows-backup', 'onedrive-kfm') {
            New-Source -Source $name -State $State[$name] -Count $Count[$name]
        }
    }
}

Describe 'Test-BackupStatus' -Tag 'check' {
    Context 'unelevated' {
        BeforeAll {
            Mock Test-IsElevated { $false }
            Mock Get-BackupSignal {
                New-SourceSet -State @{
                    'system-image' = 'unknown'; 'restore-points' = 'needs-admin'; 'file-history' = 'absent'
                    'windows-backup' = 'present'; 'onedrive-kfm' = 'absent'
                }
            }
            $script:Result = Invoke-BackupStatus
        }

        It 'is UNKNOWN while a source needs admin, even with one present' {
            $script:Result.severity | Should -Be 'UNKNOWN'
            { Assert-CheckResult $script:Result } | Should -Not -Throw
        }

        It 'asks the adapter for the unelevated read' {
            Should -Invoke Get-BackupSignal -Times 1 -Scope Context -ParameterFilter { $Elevated -eq $false }
        }

        It 'names the elevated-only fields and leaves them null' {
            $script:Result.detail.admin_fields | Should -Be @('restore_points', 'system_image')
            $script:Result.detail.restore_points | Should -BeNullOrEmpty
            $script:Result.detail.system_image | Should -BeNullOrEmpty
            $script:Result.detail.needs_admin_count | Should -Be 1
            $script:Result.detail.protected_count | Should -Be 1
        }

        It 'carries one source row per signal' {
            @($script:Result.detail.sources).Count | Should -Be 5
            ($script:Result.detail.sources | Where-Object source -EQ 'windows-backup').state | Should -Be 'present'
        }

        It 'states the System Image Backup deprecation' {
            $script:Result.summary | Should -BeLike "*$script:Deprecation*"
        }
    }

    Context 'elevated' {
        BeforeAll { Mock Test-IsElevated { $true } }

        It 'is WARN when no source is present, and still states the deprecation' {
            Mock Get-BackupSignal {
                New-SourceSet -State @{
                    'system-image' = 'unknown'; 'restore-points' = 'absent'; 'file-history' = 'absent'
                    'windows-backup' = 'absent'; 'onedrive-kfm' = 'absent'
                } -Count @{ 'system-image' = 0; 'restore-points' = 0 }
            }
            $result = Invoke-BackupStatus
            $result.severity | Should -Be 'WARN'
            $result.summary | Should -BeLike "*$script:Deprecation*"
            $result.detail.protected_count | Should -Be 0
        }

        It 'is OK with one present source and reports the elevated counts' {
            Mock Get-BackupSignal {
                New-SourceSet -State @{
                    'system-image' = 'unknown'; 'restore-points' = 'present'; 'file-history' = 'absent'
                    'windows-backup' = 'absent'; 'onedrive-kfm' = 'absent'
                } -Count @{ 'system-image' = 0; 'restore-points' = 3 }
            }
            $result = Invoke-BackupStatus
            $result.severity | Should -Be 'OK'
            $result.detail.restore_points | Should -Be 3
            $result.detail.system_image | Should -Be 0
            $result.detail.PSObject.Properties['admin_fields'] | Should -BeNullOrEmpty
        }

        It 'is UNKNOWN for a source state outside the closed set' {
            Mock Get-BackupSignal {
                New-SourceSet -State @{
                    'system-image' = 'unknown'; 'restore-points' = 'present'; 'file-history' = 'odd'
                    'windows-backup' = 'absent'; 'onedrive-kfm' = 'absent'
                }
            }
            (Invoke-BackupStatus).severity | Should -Be 'UNKNOWN'
        }

        It 'still states the deprecation when the read throws' {
            Mock Get-BackupSignal { throw 'read failed' }
            $result = Invoke-BackupStatus
            $result.severity | Should -Be 'UNKNOWN'
            $result.summary | Should -BeLike "*$script:Deprecation*"
        }
    }
}
