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
            $Signed = $null, $Foreign = $null, $PathIsAbsolute = $false, $UnderBrowserInstall = $null,
            [string] $Name = "Ext name")
        $recordArgs = @{
            Browser = $Browser; ProfileDir = 'Default'; ExtId = $ExtId; Name = $Name; Version = '1.0'
            LocationKind = $Kind; FromWebstore = $FromWebstore; Enabled = $true; ApiPermissions = $Api
            HostPatterns = $Hosts; Signed = $Signed; ForeignInstall = $Foreign
        }
        if ($Browser -ne 'firefox') {
            $recordArgs['LocationCode'] = 1
            $recordArgs['PathIsAbsolute'] = $PathIsAbsolute
            $recordArgs['UnderBrowserInstall'] = $UnderBrowserInstall
        }
        New-ExtensionRecord @recordArgs
    }

    function Get-TestRead {
        param([string] $Browser, [object[]] $Extensions = @(), [string] $ReadState = 'ok', [int] $Stubs = 0)
        [pscustomobject]@{
            Browser = $Browser; ReadState = $ReadState; ProfileCount = 1; StubsSkipped = $Stubs
            Profiles = @([pscustomobject]@{ ProfileDir = 'Default'; ReadState = $ReadState }); Extensions = $Extensions
        }
    }

    function Get-TestEntry {
        param([string] $ExtId, [bool] $OffStore = $false, [string] $ValueName = '1')
        [pscustomobject]@{ ValueName = $ValueName; ExtId = $ExtId; UpdateUrl = $(if ($OffStore) { 'https://updates.example.test/crx' }); OffStore = $OffStore }
    }

    function Get-TestPolicy {
        param([object[]] $Forcelist = @(), [object[]] $Settings = @(), [string] $ReadState = 'ok', $DomainJoined = $false)
        [pscustomobject]@{
            ReadState = $ReadState; DomainState = 'ok'; DomainJoined = $DomainJoined
            Policies  = @(
                [pscustomobject]@{ Browser = 'edge'; Hive = 'hklm'; Kind = 'forcelist'; Matched = $Forcelist.Count -gt 0; Entries = $Forcelist }
                [pscustomobject]@{ Browser = 'edge'; Hive = 'hklm'; Kind = 'extension-settings'; Matched = $Settings.Count -gt 0; Entries = $Settings }
            )
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

    It 'lists a store extension with ordinary permissions as INFO, naming the profile folder' {
        Register-FakeRead -Edge @(Get-TestExtension -Browser 'edge' -Api @('storage', 'tabs'))
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'INFO'
        $item = $r.detail.items[0]
        $item.key | Should -Match '^ext:[0-9a-f]{16}$'
        $item.profile | Should -Be 'Default'
        $item.title | Should -Be 'Ext name (edge, Default)'
        @($item.high_attention).Count | Should -Be 0
    }

    It 'flags <Case> as WARN' -ForEach @(
        @{ Case = 'an unpacked extension'; Ext = { Get-TestExtension -Kind 'unpacked' -FromWebstore $false -PathIsAbsolute $true } }
        @{ Case = 'a command-line extension'; Ext = { Get-TestExtension -Kind 'command-line' -FromWebstore $false } }
        @{ Case = 'a store-location extension not from the web store'; Ext = { Get-TestExtension -FromWebstore $false } }
        @{ Case = 'a store extension with an absolute install path'; Ext = { Get-TestExtension -PathIsAbsolute $true } }
        @{ Case = 'a policy-location extension no policy names'; Ext = { Get-TestExtension -Kind 'policy' } }
        @{ Case = 'a component outside the browser install'; Ext = { Get-TestExtension -Kind 'component' -PathIsAbsolute $true -UnderBrowserInstall $false } }
        @{ Case = 'a component when the install folder could not be read'; Ext = { Get-TestExtension -Kind 'component' -PathIsAbsolute $true } }
        @{ Case = 'a debugger permission'; Ext = { Get-TestExtension -Api @('debugger') } }
        @{ Case = 'access to all sites'; Ext = { Get-TestExtension -Hosts @('<all_urls>') } }
        @{ Case = 'an unsigned Firefox add-on'; Ext = { Get-TestExtension -Browser 'firefox' -FromWebstore $null -Signed $false -Foreign $false } }
        @{ Case = 'a Firefox add-on another program installed'; Ext = { Get-TestExtension -Browser 'firefox' -FromWebstore $null -Signed $true -Foreign $true } }
    ) {
        Register-FakeRead -Chrome @(& $Ext)
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'WARN'
        $r.detail.items[0].severity | Should -Be 'WARN'
        @($r.detail.items[0].reasons).Count | Should -BeGreaterThan 0
    }

    It 'does not flag a verified component extension for its permissions' {
        Register-FakeRead -Chrome @(Get-TestExtension -Kind 'component' -FromWebstore $false -Api @('nativeMessaging') `
                -Hosts @('<all_urls>') -PathIsAbsolute $true -UnderBrowserInstall $true)
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'INFO'
        @($r.detail.items[0].high_attention) | Should -Be @('<all_urls>', 'nativeMessaging')
    }

    It 'accepts a policy-location extension a forcelist or ExtensionSettings entry names' {
        Register-FakeRead -Chrome @() -Edge @(
            (Get-TestExtension -Browser 'edge' -Kind 'policy' -ExtId 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
            (Get-TestExtension -Browser 'edge' -Kind 'policy' -ExtId 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
        ) -Policy (Get-TestPolicy -Forcelist @(Get-TestEntry 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') `
                -Settings @(Get-TestEntry 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -ValueName $null))
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'INFO'
        @($r.detail.items.policy_hive) | Should -Be @('hklm', 'hklm')
    }

    It 'calls an off-store forcelist entry listed-off-store off a domain only when no extension with that id is installed' {
        $policy = Get-TestPolicy -Forcelist @(
            (Get-TestEntry 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -OffStore $true)
            (Get-TestEntry 'cccccccccccccccccccccccccccccccc' -OffStore $true -ValueName '2')
            (Get-TestEntry 'dddddddddddddddddddddddddddddddd' -ValueName '3')
        )
        Register-FakeRead -Edge @(Get-TestExtension -Browser 'edge' -Kind 'policy' -ExtId 'cccccccccccccccccccccccccccccccc') -Policy $policy
        $r = Invoke-BrowserExtensionsAsObject
        @($r.detail.policy_entries.install_state) | Should -Be @('listed-off-store', 'listed', 'listed')
        $r.detail.blocked_marker_count | Should -Be 1
        $r.detail.policy_entry_count | Should -Be 3
    }

    It 'calls nothing off-store on a domain-joined machine' {
        Register-FakeRead -Policy (Get-TestPolicy -DomainJoined $true -Forcelist @(Get-TestEntry 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -OffStore $true))
        (Invoke-BrowserExtensionsAsObject).detail.policy_entries[0].install_state | Should -Be 'listed'
    }

    It 'keeps a muted WARN item listed without raising the check' {
        Register-FakeRead -Chrome @(Get-TestExtension -Kind 'unpacked' -FromWebstore $false)
        $key = Get-FindingKey -Kind 'ext' -Identity @('chrome', 'Default', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
        $r = Invoke-BrowserExtensionsAsObject -MutedKeys @($key)
        $r.severity | Should -Be 'OK'
        $r.detail.items[0].muted | Should -BeTrue
        $r.detail.muted_count | Should -Be 1
    }

    It 'reports UNKNOWN, never OK, when a browser could not be read' {
        Register-FakeRead -ChromeState 'denied'
        $r = Invoke-BrowserExtensionsAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.severity | Should -Be 'UNKNOWN'
        $r.ran_successfully | Should -BeFalse
    }

    It 'reports UNKNOWN when a profile file failed, even with flagged and listed items' {
        Register-FakeRead -ChromeState 'error' -Chrome @(
            (Get-TestExtension -Kind 'unpacked' -FromWebstore $false)
            (Get-TestExtension -ExtId 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
        )
        $r = Invoke-BrowserExtensionsAsObject
        $r.severity | Should -Be 'UNKNOWN'
        $r.detail.items_count | Should -Be 2
        $r.detail.browsers[0].profiles[0].read_state | Should -Be 'error'
    }

    It 'reports UNKNOWN when the policy keys could not be read, even with items' {
        Register-FakeRead -Edge @(Get-TestExtension -Browser 'edge') -Policy (Get-TestPolicy -ReadState 'error')
        (Invoke-BrowserExtensionsAsObject).severity | Should -Be 'UNKNOWN'
    }

    It 'keeps machine text out of the summary and sanitizes it in titles and fields' {
        $evil = "Evil$([char]0x1B)[31m$([char]0x202E)name"
        Register-FakeRead -Chrome @(Get-TestExtension -Name $evil)
        $r = Invoke-BrowserExtensionsAsObject
        $r.summary | Should -Not -Match 'Evil'
        $r.detail.items[0].name | Should -Not -Match "[$([char]0x1B)$([char]0x202E)]"
        $r.detail.items[0].title | Should -Not -Match "[$([char]0x1B)$([char]0x202E)]"
    }
}
