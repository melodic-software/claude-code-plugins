#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-DnsHealth.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')

    function Invoke-DnsHealthAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
}

Describe 'Test-DnsHealth -- baseline' -Tag 'check' {
    It 'reports OK when DNS resolves and gateway is reachable' {
        Mock Resolve-DnsName { @([pscustomobject]@{ Name = 'mock'; IPAddress = '1.2.3.4' }) }
        Mock Get-NetRoute { [pscustomobject]@{ NextHop = '192.168.1.1'; RouteMetric = 0 } }
        Mock Test-Connection { $true }

        $result = Invoke-DnsHealthAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'dns-health'
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-DnsHealth -- severity rubric' -Tag 'check' {
    It 'reports WARN when one DNS target fails but gateway is reachable' {
        $state = @{ callIndex = 0 }
        Mock Resolve-DnsName ({
                $state.callIndex++
                if ($state.callIndex -eq 1) {
                    return @([pscustomobject]@{ Name = 'microsoft.com'; IPAddress = '1.2.3.4' })
                }
                throw 'DNS resolution failed'
            }.GetNewClosure())
        Mock Get-NetRoute { [pscustomobject]@{ NextHop = '192.168.1.1'; RouteMetric = 0 } }
        Mock Test-Connection { $true }

        $result = Invoke-DnsHealthAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.targets_failed | Should -Be 1
    }

    It 'reports CRIT when default gateway is unreachable' {
        Mock Resolve-DnsName { @([pscustomobject]@{ Name = 'mock'; IPAddress = '1.2.3.4' }) }
        Mock Get-NetRoute { [pscustomobject]@{ NextHop = '192.168.1.1'; RouteMetric = 0 } }
        Mock Test-Connection { $false }

        $result = Invoke-DnsHealthAsObject
        $result.severity | Should -Be 'CRIT'
        $result.summary | Should -Match 'gateway.*unreachable'
    }

    It 'reports WARN (not INFO) when DNS fails and gateway probe fails too (regression)' {
        # Regression: when Get-NetRoute fails the script catches and leaves
        # $gatewayReachable as $null. Previous code downgraded that to INFO
        # regardless of DNS state, under-reporting actionable DNS failures.
        # DNS WARN must survive the unknown-gateway case.
        Mock Resolve-DnsName { throw 'DNS resolution failed' }
        Mock Get-NetRoute { throw 'Get-NetRoute failed' }

        $result = Invoke-DnsHealthAsObject
        $result.severity | Should -Be 'WARN' -Because 'DNS failures are actionable even without gateway signal'
        $result.detail.targets_failed | Should -BeGreaterThan 0
        $result.detail.gateway_reachable | Should -BeNullOrEmpty
        $result.summary | Should -Match 'gateway unknown'
    }

    It 'reports INFO when gateway probe fails but DNS is fine' {
        Mock Resolve-DnsName { @([pscustomobject]@{ Name = 'mock'; IPAddress = '1.2.3.4' }) }
        Mock Get-NetRoute { throw 'Get-NetRoute failed' }

        $result = Invoke-DnsHealthAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.targets_failed | Should -Be 0
    }
}
