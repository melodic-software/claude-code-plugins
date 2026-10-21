#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-AppLastUse' `
        -LibScript 'New-FindingItem.ps1', 'Get-InstalledApp.ps1', 'Read-UserAssist.ps1', 'Get-EvidenceWindow.ps1', 'Get-ElevatedAppEvidence.ps1'

    function Invoke-AppLastUse {
        param([string[]] $MutedKeys = @())
        ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }

    function New-App {
        param([string] $Key, [string] $Kind = 'win32', [string] $InstallDir, [string] $ExePath, [string] $Family)
        [pscustomobject]@{
            Key = $Key; Name = $Key; Kind = $Kind; InstallDate = $null
            InstallDir = $InstallDir ? $InstallDir : $null; ExePath = $ExePath ? $ExePath : $null
            PackageFamilyName = $Family ? $Family : $null
        }
    }

    function New-Launch {
        param([string] $Name, [string] $Path, [Nullable[datetime]] $LastRun)
        [pscustomobject]@{ Name = $Name; Path = $Path; LastRun = $LastRun }
    }

    $script:Start = [datetime]::new(2026, 6, 27, 1, 52, 48, [DateTimeKind]::Utc)
    $script:Launched = [datetime]::new(2026, 9, 1, 12, 0, 0, [DateTimeKind]::Utc)

    # One app per verdict path. The check runs mocks in its own scope, so the
    # fixtures are captured into each mock's closure.
    function Set-Host {
        param(
            [string] $UserAssistState = 'ok',
            [string] $ElevatedState = 'denied',
            [object[]] $Prefetch = @(),
            [object[]] $Bam = @()
        )
        $start = $script:Start
        $launched = $script:Launched
        Mock Get-EvidenceWindow ({
                [pscustomobject]@{ ReadState = 'ok'; Start = $start; Days = 116; Sources = @() }
            }.GetNewClosure())
        Mock Get-InstalledApp {
            [pscustomobject]@{ ReadState = 'ok'; Apps = @(
                    New-App -Key 'Notes' -Kind 'store' -Family 'Contoso.Notes_abc123'
                    New-App -Key 'Paint' -Kind 'store' -Family 'Contoso.Paint_abc123'
                    New-App -Key 'Editor' -InstallDir 'X:\Apps\Editor' -ExePath 'X:\Apps\Editor\editor.exe'
                    New-App -Key 'Viewer' -InstallDir 'X:\Apps\Viewer'
                    New-App -Key 'Driver'
                    New-App -Key 'Shared' -InstallDir 'X:\Apps'
                )
            }
        }
        $ua = @(
            New-Launch -Name 'Contoso.Notes_abc123!App' -LastRun $launched
            New-Launch -Name '{GUID}\Apps\Editor\editor.exe' -Path 'X:\Apps\Editor\editor.exe' -LastRun $launched
            New-Launch -Name 'X:\Apps\Other\other.exe' -Path 'X:\Apps\Other\other.exe' -LastRun $launched
        )
        $uaState = $UserAssistState
        Mock Read-UserAssist ({
                [pscustomobject]@{ ReadState = $uaState; Entries = ($uaState -eq 'ok' ? $ua : @()) }
            }.GetNewClosure())
        $state = $ElevatedState
        $prefetchEntries = $Prefetch
        $bamEntries = $Bam
        Mock Get-ElevatedAppEvidence ({
                [pscustomobject]@{ Source = 'prefetch'; ReadState = $state; Entries = $prefetchEntries }
                [pscustomobject]@{ Source = 'bam'; ReadState = $state; Entries = $bamEntries }
            }.GetNewClosure())
    }

    function Get-AppItem {
        param($Result, [string] $Name)
        $Result.detail.items | Where-Object name -EQ $Name
    }
}

Describe 'Test-AppLastUse' -Tag 'check' {
    Context 'standard token' {
        BeforeEach { Set-Host }

        It 'emits a schema-valid result in the config category' {
            $result = Invoke-AppLastUse
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.id | Should -Be 'app-last-use'
            $result.category | Should -Be 'config'
        }

        It 'gives each app the verdict its launch records support' {
            $result = Invoke-AppLastUse

            (Get-AppItem $result 'Notes').verdict | Should -Be 'launched'
            (Get-AppItem $result 'Notes').last_launch_source | Should -Be 'userassist'
            (Get-AppItem $result 'Editor').verdict | Should -Be 'launched'
            (Get-AppItem $result 'Viewer').verdict | Should -Be 'no-launch-recorded'
            (Get-AppItem $result 'Paint').verdict | Should -Be 'no-evidence'
            (Get-AppItem $result 'Driver').verdict | Should -Be 'no-evidence'
        }

        It 'does not credit a launch under a folder shared by many apps' {
            (Get-AppItem (Invoke-AppLastUse) 'Shared').verdict | Should -Be 'no-evidence'
        }

        It 'states a missing launch as "no launch recorded since" the evidence start, never as a month count' {
            $result = Invoke-AppLastUse

            (Get-AppItem $result 'Viewer').title | Should -Be 'Viewer: no launch recorded since 2026-06-27'
            $result.summary | Should -Match 'no launch recorded since 2026-06-27'
            ($result | ConvertTo-Json -Depth 10) | Should -Not -Match '\d+ months?'
            ([datetime]$result.detail.evidence_start).ToUniversalTime() | Should -Be $script:Start
        }

        It 'counts verdicts and reports the UserAssist read state' {
            $detail = (Invoke-AppLastUse).detail
            $detail.apps_count | Should -Be 6
            $detail.launched_count | Should -Be 2
            $detail.no_launch_count | Should -Be 1
            $detail.no_evidence_count | Should -Be 3
            $detail.userassist_state | Should -Be 'ok'
            $detail.items_count | Should -Be 6
        }

        It 'reads INFO, and names the elevated-only fields as admin fields' {
            $result = Invoke-AppLastUse
            $result.severity | Should -Be 'INFO'
            $result.needs_admin | Should -BeFalse
            @($result.detail.admin_fields | Sort-Object) | Should -Be @('bam_state', 'prefetch_state')
            $result.detail.prefetch_state | Should -Be 'denied'
        }
    }

    It 'finds no launch anywhere and reads UNKNOWN when UserAssist cannot be decoded' {
        Set-Host -UserAssistState 'error'

        $result = Invoke-AppLastUse

        $result.severity | Should -Be 'UNKNOWN'
        $result.detail.userassist_state | Should -Be 'error'
        $result.detail.launched_count | Should -Be 0
        $result.detail.no_launch_count | Should -Be 0
    }

    It 'reads OK once every INFO app is muted and every source reads' {
        Set-Host -ElevatedState 'absent'
        $keys = 'Viewer', 'Paint', 'Driver', 'Shared' | ForEach-Object { Get-FindingKey -Kind 'app' -Identity @($_) }

        $result = Invoke-AppLastUse -MutedKeys $keys

        $result.severity | Should -Be 'OK'
        $result.detail.muted_count | Should -Be 4
        (Get-AppItem $result 'Viewer').muted | Should -BeTrue
        $result.detail.PSObject.Properties['admin_fields'] | Should -BeNullOrEmpty
    }

    It 'takes a launch from Prefetch by executable name and from BAM by volume path when elevated' {
        Set-Host -ElevatedState 'ok' -Prefetch @(
            [pscustomobject]@{ ExeName = 'editor.exe'; LastRun = [datetime]::new(2026, 10, 1, 0, 0, 0, [DateTimeKind]::Utc) }
        ) -Bam @(
            [pscustomobject]@{ ExeName = 'viewer.exe'; Path = '\Apps\Viewer\viewer.exe'; LastRun = [datetime]::new(2026, 8, 1, 0, 0, 0, [DateTimeKind]::Utc) }
        )

        $result = Invoke-AppLastUse

        (Get-AppItem $result 'Editor').last_launch_source | Should -Be 'prefetch'
        (Get-AppItem $result 'Viewer').verdict | Should -Be 'launched'
        (Get-AppItem $result 'Viewer').last_launch_source | Should -Be 'bam'
    }
}
