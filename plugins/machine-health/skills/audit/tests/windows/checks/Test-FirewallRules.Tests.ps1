#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-FirewallRules.ps1, with
Get-FirewallRuleInventory mocked. The plan fixes the check at INFO in every
case, including a failed read; items are keyed by rule Name, or by version
pattern, direction, protocol and port for per-version rules.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-FirewallRules' `
        -LibScript 'New-FindingItem.ps1', 'Get-FirewallRuleInventory.ps1'

    function Invoke-FirewallRulesAsObject {
        param([string[]] $MutedKeys = @())
        return ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }

    $script:Root = Join-Path $env:ProgramFiles 'Vendor'

    function Get-TestRecord {
        param([string] $Name, [string] $Program, [string] $Pattern = $null, [string] $State = 'exists',
            $Protocol = 'TCP', $LocalPort = '8080', [bool] $PortRead = $true)
        [pscustomobject]@{
            Name = $Name; DisplayName = "Display $Name"; Program = $Program; ProgramPattern = $Pattern
            ProgramState = $State; Origin = 'PersistentStore'; Protocol = ($PortRead ? $Protocol : $null)
            LocalPort = ($PortRead ? $LocalPort : $null); PortRead = $PortRead; Profile = 'Any'; DisplayGroup = 'Vendor'
        }
    }

    # Mock bodies reach the fake inventory by closure, not through $script:.
    $script:Fake = @{}
    $fake = $script:Fake
    Set-Item -Path function:Get-FakeInventory -Value ({ $fake['inv'] }.GetNewClosure())

    function Register-FakeInventory {
        param([object[]] $Rules = @(), [string] $ReadState = 'ok', [string] $PortReadState = 'ok')
        $script:Fake['inv'] = [pscustomobject]@{
            ReadState = $ReadState; PortReadState = $PortReadState; PortFallbackReads = 0
            RuleCount = 500; ForeignCount = 200; Rules = $Rules
        }
    }
}

Describe 'Test-FirewallRules' -Tag 'check' {
    BeforeEach {
        Register-FakeInventory
        Mock Get-FirewallRuleInventory { Get-FakeInventory }
    }

    It 'reports INFO, never OK, with no candidate rules' {
        $r = Invoke-FirewallRulesAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.error | Should -BeNullOrEmpty
        $r.id | Should -Be 'firewall-rules'
        $r.category | Should -Be 'security'
        $r.needs_admin | Should -BeFalse
        $r.severity | Should -Be 'INFO'
        $r.detail.baseline_hosts | Should -Be 1
        $r.detail.items_count | Should -Be 0
    }

    It 'stays INFO when a rule points at a program that no longer exists, and names it' {
        Register-FakeInventory -Rules @(Get-TestRecord -Name 'old' -Program (Join-Path $script:Root 'old.exe') -State 'not-found')
        $r = Invoke-FirewallRulesAsObject
        $r.severity | Should -Be 'INFO'
        $r.detail.not_found_count | Should -Be 1
        $r.detail.items[0].severity | Should -Be 'INFO'
        $r.summary | Should -Match 'Display old'
    }

    It 'stays INFO, with ran_successfully true and read_state set, when the inventory read fails' {
        Register-FakeInventory -ReadState 'denied'
        $r = Invoke-FirewallRulesAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.severity | Should -Be 'INFO'
        $r.ran_successfully | Should -BeTrue
        $r.detail.read_state | Should -Be 'denied'
        $r.summary | Should -Match 'could not be read'
    }

    It 'stays INFO when the adapter throws' {
        Mock Get-FirewallRuleInventory { throw 'provider gone' }
        $r = Invoke-FirewallRulesAsObject
        $r.severity | Should -Be 'INFO'
        $r.detail.read_state | Should -Be 'error'
        $r.notes | Should -Match 'provider gone'
    }

    It 'keys an ungrouped rule by its Name, even with protocol and port unread' {
        Register-FakeInventory -Rules @(Get-TestRecord -Name 'vendor-rule' -Program (Join-Path $script:Root 'a.exe') -PortRead $false)
        $r = Invoke-FirewallRulesAsObject
        $item = $r.detail.items[0]
        $item.key | Should -Be (Get-FindingKey -Kind 'firewall' -Identity @('vendor-rule'))
        $item.rule_name | Should -Be 'vendor-rule'
        $item.protocol | Should -BeNullOrEmpty
    }

    It 'groups per-version rules into one item whose key survives a version change' {
        $pattern = Join-Path $script:Root '*\host.exe'
        Register-FakeInventory -Rules @(
            (Get-TestRecord -Name 'v1' -Program (Join-Path $script:Root '1.0.1\host.exe') -Pattern $pattern -State 'not-found')
            (Get-TestRecord -Name 'v2' -Program (Join-Path $script:Root '1.0.2\host.exe') -Pattern $pattern -State 'exists')
        )
        $first = Invoke-FirewallRulesAsObject
        $first.detail.items_count | Should -Be 1
        $first.detail.grouped_rule_count | Should -Be 2
        $item = $first.detail.items[0]
        $item.rule_count | Should -Be 2
        $item.rule_name | Should -BeNullOrEmpty
        $item.program | Should -Be $pattern
        $item.program_state | Should -Be 'exists'
        $item.key | Should -Be (Get-FindingKey -Kind 'firewall' -Identity @($pattern, 'inbound', 'TCP', '8080'))

        Register-FakeInventory -Rules @(Get-TestRecord -Name 'v3' -Program (Join-Path $script:Root '2.0.0\host.exe') -Pattern $pattern)
        (Invoke-FirewallRulesAsObject).detail.items[0].key | Should -Be $item.key
    }

    It 'calls a group not-found only when every version is missing' {
        $pattern = Join-Path $script:Root '*\host.exe'
        Register-FakeInventory -Rules @(
            (Get-TestRecord -Name 'v1' -Program (Join-Path $script:Root '1.0\host.exe') -Pattern $pattern -State 'not-found')
            (Get-TestRecord -Name 'v2' -Program (Join-Path $script:Root '2.0\host.exe') -Pattern $pattern -State 'unknown')
        )
        (Invoke-FirewallRulesAsObject).detail.items[0].program_state | Should -Be 'unknown'
    }

    It 'lists a per-version rule with unread protocol and port without a key' {
        Register-FakeInventory -PortReadState 'denied' -Rules @(
            Get-TestRecord -Name 'v1' -Program (Join-Path $script:Root '1.0\host.exe') -Pattern (Join-Path $script:Root '*\host.exe') -PortRead $false
        )
        $r = Invoke-FirewallRulesAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.severity | Should -Be 'INFO'
        $r.detail.items[0].key | Should -BeNullOrEmpty
        $r.detail.items[0].muted | Should -BeFalse
        $r.detail.items[0].unkeyed_reason | Should -Not -BeNullOrEmpty
        $r.detail.unkeyed_count | Should -Be 1
        $r.detail.port_read_state | Should -Be 'denied'
    }

    It 'marks a muted item and counts it' {
        Register-FakeInventory -Rules @(Get-TestRecord -Name 'vendor-rule' -Program (Join-Path $script:Root 'a.exe'))
        $key = Get-FindingKey -Kind 'firewall' -Identity @('vendor-rule')
        $r = Invoke-FirewallRulesAsObject -MutedKeys @($key)
        $r.detail.items[0].muted | Should -BeTrue
        $r.detail.muted_count | Should -Be 1
        $r.severity | Should -Be 'INFO'
    }
}
