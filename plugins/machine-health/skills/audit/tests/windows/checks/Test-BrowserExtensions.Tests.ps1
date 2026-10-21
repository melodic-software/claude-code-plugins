#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-BrowserExtensions.ps1, with the three
adapters mocked. Expected severities follow the rubric in check-catalog.md
section 23 (owner-approved judgment rules).
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-BrowserExtensions' `
        -LibScript 'New-FindingItem.ps1', 'Get-ChromiumExtension.ps1', 'Get-FirefoxExtension.ps1', 'Get-ExtensionPolicy.ps1'

    function Invoke-BrowserExtensionsAsObject {
        param([string[]] $MutedKeys = @())
        return ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }

    function Get-TestExtension {
        param([string] $Browser = 'chrome', [string] $ExtId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            [string] $Kind = 'store', $FromWebstore = $true, [string[]] $Api = @(), [string[]] $Hosts = @(),
            $Signed = $null, $Foreign = $null)
        [pscustomobject]@{
            Browser = $Browser; ProfileDir = 'Default'; ProfileName = 'Personal'; ExtId = $ExtId
            Name = "Ext $ExtId"; Version = '1.0'; LocationCode = 1; LocationKind = $Kind
            FromWebstore = $FromWebstore; Enabled = $true; ApiPermissions = $Api; HostPatterns = $Hosts
            Signed = $Signed; ForeignInstall = $Foreign
        }
    }

    function Get-TestRead {
        param([string] $Browser, [object[]] $Extensions = @(), [string] $ReadState = 'ok', [int] $Stubs = 0)
        [pscustomobject]@{ Browser = $Browser; ReadState = $ReadState; ProfileCount = 1; StubsSkipped = $Stubs; Extensions = $Extensions }
    }

    function Get-TestPolicy {
        param([object[]] $Forcelist = @(), [string] $ReadState = 'ok')
        [pscustomobject]@{
            ReadState = $ReadState; DomainState = 'ok'; DomainJoined = $false
            Policies  = @([pscustomobject]@{
                    Browser = 'edge'; Hive = 'hklm'; Kind = 'forcelist'; Entries = $Forcelist.Count
                    Matched = $Forcelist.Count -gt 0; BlockedCount = @($Forcelist | Where-Object InstallState -eq 'listed-but-blocked').Count
                    Forcelist = $Forcelist
                })
        }
    }

    # Mock bodies run inside the check script, where $script: names the check's
    # scope, so the fake reads live in one table the mock reaches by closure.
    $script:Reads = @{}
    $reads = $script:Reads
    Set-Item -Path function:Get-FakeRead -Value ({ param([string] $Name) $reads[$Name] }.GetNewClosure())

    function Register-FakeRead {
        param([object[]] $Chrome = @(), [object[]] $Edge = @(), [object[]] $Firefox = @(),
            [string] $ChromeState = 'ok', $Policy = (Get-TestPolicy))
        $script:Reads['chrome'] = Get-TestRead -Browser 'chrome' -Extensions $Chrome -ReadState $ChromeState -Stubs 3
        $script:Reads['edge'] = Get-TestRead -Browser 'edge' -Extensions $Edge -Stubs 2
        $script:Reads['firefox'] = Get-TestRead -Browser 'firefox' -Extensions $Firefox
        $script:Reads['policy'] = $Policy
    }
}

Describe 'Test-BrowserExtensions' -Tag 'check' {
    BeforeEach {
        Register-FakeRead
        Mock Get-ChromiumExtension { Get-FakeRead $Browser }
        Mock Get-FirefoxExtension { Get-FakeRead 'firefox' }
        Mock Get-ExtensionPolicy { Get-FakeRead 'policy' }
    }

    It 'reports OK with no extensions and every source read' {
        $r = Invoke-BrowserExtensionsAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.error | Should -BeNullOrEmpty
        $r.id | Should -Be 'browser-extensions'
        $r.category | Should -Be 'security'
        $r.needs_admin | Should -BeFalse
        $r.severity | Should -Be 'OK'
        $r.detail.items_count | Should -Be 0
        $r.detail.stubs_skipped | Should -Be 5
    }

    It 'lists a store extension with ordinary permissions as INFO' {
        Register-FakeRead -Edge @(Get-TestExtension -Browser 'edge' -Api @('storage', 'tabs'))
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'INFO'
        $item = $r.detail.items[0]
        $item.key | Should -Match '^ext:[0-9a-f]{16}$'
        $item.browser | Should -Be 'edge'
        $item.profile | Should -Be 'Personal'
        $item.location_kind | Should -Be 'store'
        @($item.high_attention).Count | Should -Be 0
        $r.detail.extension_count | Should -Be 1
    }

    It 'flags <Case> as WARN' -TestCases @(
        @{ Case = 'an unpacked extension'; Ext = { Get-TestExtension -Kind 'unpacked' -FromWebstore $false } }
        @{ Case = 'a command-line extension'; Ext = { Get-TestExtension -Kind 'command-line' -FromWebstore $false } }
        @{ Case = 'a store-location extension not from the web store'; Ext = { Get-TestExtension -FromWebstore $false } }
        @{ Case = 'a debugger permission'; Ext = { Get-TestExtension -Api @('debugger') } }
        @{ Case = 'access to all sites'; Ext = { Get-TestExtension -Hosts @('<all_urls>') } }
        @{ Case = 'an unsigned Firefox add-on'; Ext = { Get-TestExtension -Browser 'firefox' -FromWebstore $null -Signed $false -Foreign $false } }
        @{ Case = 'a Firefox add-on another program installed'; Ext = { Get-TestExtension -Browser 'firefox' -FromWebstore $null -Signed $true -Foreign $true } }
    ) {
        Register-FakeRead -Chrome @(& $Ext)
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'WARN'
        $r.detail.items[0].severity | Should -Be 'WARN'
    }

    It 'does not flag a component extension for its permissions' {
        Register-FakeRead -Chrome @(Get-TestExtension -Kind 'component' -FromWebstore $false -Api @('nativeMessaging') -Hosts @('<all_urls>'))
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'INFO'
        @($r.detail.items[0].high_attention) | Should -Be @('<all_urls>', 'nativeMessaging')
        $r.detail.high_attention_count | Should -Be 1
    }

    It 'keeps a muted WARN item listed without raising the check' {
        Register-FakeRead -Chrome @(Get-TestExtension -Kind 'unpacked' -FromWebstore $false)
        $key = Get-FindingKey -Kind 'ext' -Identity @('chrome', 'Default', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
        $r = Invoke-BrowserExtensionsAsObject -MutedKeys @($key)
        $r.severity | Should -Be 'OK'
        $r.detail.items[0].muted | Should -BeTrue
        $r.detail.muted_count | Should -Be 1
        $r.detail.items_count | Should -Be 1
    }

    It 'keys the item by browser, profile directory and id, not by display name' {
        Register-FakeRead -Chrome @(Get-TestExtension)
        $first = (Invoke-BrowserExtensionsAsObject).detail.items[0].key
        $renamed = Get-TestExtension
        $renamed.ProfileName = 'Renamed'
        Register-FakeRead -Chrome @($renamed)
        (Invoke-BrowserExtensionsAsObject).detail.items[0].key | Should -Be $first
    }

    It 'reports UNKNOWN, never OK, when a browser could not be read' {
        Register-FakeRead -ChromeState 'denied'
        $r = Invoke-BrowserExtensionsAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.severity | Should -Be 'UNKNOWN'
        $r.summary | Should -Match 'chrome'
        $r.ran_successfully | Should -BeFalse
    }

    It 'reports UNKNOWN when the policy keys could not be read' {
        Register-FakeRead -Policy (Get-TestPolicy -ReadState 'error')
        (Invoke-BrowserExtensionsAsObject).severity | Should -Be 'UNKNOWN'
    }

    It 'lists policy entries with their hive and install state and labels the forced extension' {
        $forcelist = @(
            [pscustomobject]@{ ValueName = '1'; ExtId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; UpdateUrl = $null; InstallState = 'listed' }
            [pscustomobject]@{ ValueName = '2'; ExtId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; UpdateUrl = 'https://updates.example.test/crx'; InstallState = 'listed-but-blocked' }
        )
        Register-FakeRead -Edge @(Get-TestExtension -Browser 'edge' -Kind 'policy') -Policy (Get-TestPolicy -Forcelist $forcelist)
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'INFO'
        $r.detail.policy_entry_count | Should -Be 2
        $r.detail.blocked_marker_count | Should -Be 1
        @($r.detail.policy_entries.install_state) | Should -Be @('listed', 'listed-but-blocked')
        $r.detail.policy_entries[0].hive | Should -Be 'hklm'
        $r.detail.items[0].policy_hive | Should -Be 'hklm'
        $r.detail.policy[0].kind | Should -Be 'forcelist'
    }
}
