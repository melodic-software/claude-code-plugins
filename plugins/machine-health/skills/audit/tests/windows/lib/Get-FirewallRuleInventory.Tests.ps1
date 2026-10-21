#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.DESCRIPTION
Synthetic cases from the foreign-firewall probe findings: SystemDefaults names
mark built-in rules, Test-Path writes an access-denied record for an existing
file under an untraversable folder, and the unelevated bulk port-filter read
stops partway with a PermissionDenied error.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-FirewallRuleInventory.ps1'

    $script:Root = Join-Path $TestDrive 'Programs'

    function Get-TestRule {
        param([string] $Name, [string] $Source = 'Local', [string] $Enabled = 'True',
            [string] $Direction = 'Inbound', [string] $Action = 'Allow')
        # A real (offline) CimInstance: the cmdletized port-filter cmdlet converts
        # -AssociatedNetFirewallRule to CimInstance even when mocked.
        $rule = [Microsoft.Management.Infrastructure.CimInstance]::new('MachineHealthTestRule')
        $rule.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create(
                'InstanceID', $Name, [Microsoft.Management.Infrastructure.CimFlags]::Key))
        $props = [ordered]@{
            Name = $Name; DisplayName = "Display $Name"; PolicyStoreSourceType = $Source
            PolicyStoreSource = 'PersistentStore'; Enabled = $Enabled; Direction = $Direction; Action = $Action
            Profile = 'Any'; DisplayGroup = 'Vendor'
        }
        foreach ($k in $props.Keys) { $rule | Add-Member -NotePropertyName $k -NotePropertyValue $props[$k] }
        # The parameter also checks this type name; added last so the class's
        # type-data members do not collide with the note properties above.
        $rule.PSObject.TypeNames.Insert(0, 'Microsoft.Management.Infrastructure.CimInstance#root/standardcimv2/MSFT_NetFirewallRule')
        $rule
    }

    function Get-DeniedRecord {
        [System.Management.Automation.ErrorRecord]::new(
            [System.UnauthorizedAccessException]::new('Access is denied.'), 'Denied',
            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
    }

    # Mock bodies reach the fake tables by closure, not through $script:.
    $script:Fake = @{}
    $fake = $script:Fake
    Set-Item -Path function:Get-Fake -Value ({ param([string] $Name) $fake[$Name] }.GetNewClosure())

    function Register-Fake {
        param([object[]] $Rules, [string[]] $Defaults = @(), [hashtable] $Programs = @{},
            [hashtable] $Ports = @{}, [hashtable] $PerRulePorts = @{}, [switch] $PortBulkDenied,
            [string[]] $Existing = @(), [string[]] $Denied = @())
        $script:Fake['rules'] = $Rules
        $script:Fake['defaults'] = @($Defaults | ForEach-Object { [pscustomobject]@{ Name = $_ } })
        $script:Fake['apps'] = @($Programs.Keys | ForEach-Object { [pscustomobject]@{ InstanceID = $_; Program = $Programs[$_] } })
        $script:Fake['ports'] = @($Ports.Keys | ForEach-Object { [pscustomobject]@{ InstanceID = $_; Protocol = $Ports[$_][0]; LocalPort = $Ports[$_][1] } })
        $script:Fake['perRule'] = $PerRulePorts
        $script:Fake['portDenied'] = [bool]$PortBulkDenied
        $script:Fake['existing'] = $Existing
        $script:Fake['denied'] = $Denied
    }
}

Describe 'Get-VersionedProgramPattern' -Tag 'lib' {
    It 'replaces each dotted-version folder with *' {
        Get-VersionedProgramPattern -Path 'X:\Apps\WebView\131.0.2903.70\host.exe' | Should -Be 'X:\Apps\WebView\*\host.exe'
    }

    It 'returns nothing for a path with no version folder' {
        Get-VersionedProgramPattern -Path 'X:\Apps\Tool v2\tool.exe' | Should -BeNullOrEmpty
    }
}

Describe 'Get-FirewallRuleInventory' -Tag 'lib' {
    BeforeEach {
        Mock Get-NetFirewallRule {
            if ($PolicyStore -eq 'SystemDefaults') { return Get-Fake 'defaults' }
            Get-Fake 'rules'
        }
        Mock Get-NetFirewallApplicationFilter { Get-Fake 'apps' }
        Mock Get-NetFirewallPortFilter -RemoveParameterType AssociatedNetFirewallRule {
            if ($null -ne $AssociatedNetFirewallRule) {
                $name = [string]@($AssociatedNetFirewallRule)[0].CimInstanceProperties['InstanceID'].Value
                $p = (Get-Fake 'perRule')[$name]
                if ($p) { return [pscustomobject]@{ InstanceID = $name; Protocol = $p[0]; LocalPort = $p[1] } }
                return
            }
            Get-Fake 'ports'
            if (Get-Fake 'portDenied') { Write-Error -ErrorRecord (Get-DeniedRecord) }
        }
        Mock Test-Path {
            $path = @($LiteralPath)[0]
            if ($path -in (Get-Fake 'existing')) { return $true }
            if ($path -in (Get-Fake 'denied')) { Write-Error -ErrorRecord (Get-DeniedRecord) }
            return $false
        }
    }

    It 'keeps only foreign, enabled, inbound, allow rules bound to a program' {
        $prog = Join-Path $script:Root 'agent.exe'
        Register-Fake -Rules @(
            (Get-TestRule 'vendor-in')
            (Get-TestRule 'builtin-in')
            (Get-TestRule 'gpo-in' -Source 'GroupPolicy')
            (Get-TestRule 'dyn-in' -Source 'Dynamic')
            (Get-TestRule 'disabled' -Enabled 'False')
            (Get-TestRule 'outbound' -Direction 'Outbound')
            (Get-TestRule 'block' -Action 'Block')
            (Get-TestRule 'any-prog')
            (Get-TestRule 'system-prog')
        ) -Defaults @('BUILTIN-IN') -Programs @{
            'vendor-in' = $prog; 'builtin-in' = $prog; 'gpo-in' = $prog; 'dyn-in' = $prog; 'disabled' = $prog
            'outbound' = $prog; 'block' = $prog; 'any-prog' = 'Any'; 'system-prog' = 'System'
        } -Ports @{ 'vendor-in' = @('TCP', '8080') } -Existing @($prog)

        $r = Get-FirewallRuleInventory
        $r.ReadState | Should -Be 'ok'
        $r.PortReadState | Should -Be 'ok'
        $r.RuleCount | Should -Be 9
        $r.ForeignCount | Should -Be 6
        @($r.Rules.Name) | Should -Be @('vendor-in')
        $r.Rules[0].Protocol | Should -Be 'TCP'
        $r.Rules[0].LocalPort | Should -Be '8080'
        $r.Rules[0].ProgramState | Should -Be 'exists'
        $r.Rules[0].PortRead | Should -BeTrue
    }

    It 'expands environment variables in the program path' {
        Register-Fake -Rules @(Get-TestRule 'r1') -Programs @{ 'r1' = '%SystemRoot%\tool.exe' }
        (Get-FirewallRuleInventory).Rules[0].Program | Should -Be (Join-Path $env:SystemRoot 'tool.exe')
    }

    It 'reads not-found only when Test-Path writes no error, and unknown when it is denied' {
        $gone = Join-Path $script:Root 'gone.exe'
        $hidden = Join-Path $script:Root 'locked\hidden.exe'
        Register-Fake -Rules @((Get-TestRule 'gone'), (Get-TestRule 'hidden')) `
            -Programs @{ 'gone' = $gone; 'hidden' = $hidden } -Denied @($hidden)
        $byName = @{}
        (Get-FirewallRuleInventory).Rules | ForEach-Object { $byName[$_.Name] = $_ }
        $byName['gone'].ProgramState | Should -Be 'not-found'
        $byName['hidden'].ProgramState | Should -Be 'unknown'
    }

    It 'joins multi-valued local ports with commas' {
        Register-Fake -Rules @(Get-TestRule 'r1') -Programs @{ 'r1' = (Join-Path $script:Root 'a.exe') } `
            -Ports @{ 'r1' = @('TCP', @('554', '8554-8558')) }
        (Get-FirewallRuleInventory).Rules[0].LocalPort | Should -Be '554,8554-8558'
    }

    It 'records a denied bulk port read and fills only versioned rules it missed, one read each' {
        $versioned = Join-Path $script:Root '1.2.3\host.exe'
        $plain = Join-Path $script:Root 'plain.exe'
        Register-Fake -Rules @((Get-TestRule 'ver'), (Get-TestRule 'plain')) `
            -Programs @{ 'ver' = $versioned; 'plain' = $plain } -PortBulkDenied `
            -PerRulePorts @{ 'ver' = @('UDP', '5000'); 'plain' = @('TCP', '1') }
        $r = Get-FirewallRuleInventory
        $r.PortReadState | Should -Be 'denied'
        $r.PortFallbackReads | Should -Be 1
        $byName = @{}
        $r.Rules | ForEach-Object { $byName[$_.Name] = $_ }
        $byName['ver'].ProgramPattern | Should -Be (Join-Path $script:Root '*\host.exe')
        $byName['ver'].Protocol | Should -Be 'UDP'
        $byName['ver'].PortRead | Should -BeTrue
        $byName['plain'].ProgramPattern | Should -BeNullOrEmpty
        $byName['plain'].Protocol | Should -BeNullOrEmpty
        $byName['plain'].PortRead | Should -BeFalse
    }

    It 'stops per-rule port reads at the call cap and leaves the rest unread' {
        $rules = 1..($script:PortFallbackMaxCalls + 3) | ForEach-Object { Get-TestRule "v$_" }
        $programs = @{}
        $perRule = @{}
        foreach ($rule in $rules) {
            $programs[$rule.Name] = Join-Path $script:Root "$($rule.Name)\9.9\x.exe"
            $perRule[$rule.Name] = @('TCP', '1')
        }
        Register-Fake -Rules $rules -Programs $programs -PortBulkDenied -PerRulePorts $perRule
        $r = Get-FirewallRuleInventory
        $r.PortFallbackReads | Should -Be $script:PortFallbackMaxCalls
        @($r.Rules | Where-Object { -not $_.PortRead }).Count | Should -Be 3
    }

    It 'makes no per-rule port read once the time budget is spent' {
        $saved = $script:PortFallbackBudgetMs
        try {
            $script:PortFallbackBudgetMs = 0
            Register-Fake -Rules @(Get-TestRule 'ver') -Programs @{ 'ver' = (Join-Path $script:Root '1.0\x.exe') } `
                -PortBulkDenied -PerRulePorts @{ 'ver' = @('TCP', '1') }
            $r = Get-FirewallRuleInventory
            $r.PortFallbackReads | Should -Be 0
            $r.Rules[0].PortRead | Should -BeFalse
        } finally {
            $script:PortFallbackBudgetMs = $saved
        }
    }

    It 'returns a non-ok ReadState and no rules when a required read fails' {
        Mock Get-NetFirewallApplicationFilter { throw [System.UnauthorizedAccessException]::new('denied') }
        Register-Fake -Rules @(Get-TestRule 'r1')
        $r = Get-FirewallRuleInventory
        $r.ReadState | Should -Be 'denied'
        @($r.Rules).Count | Should -Be 0
    }
}
