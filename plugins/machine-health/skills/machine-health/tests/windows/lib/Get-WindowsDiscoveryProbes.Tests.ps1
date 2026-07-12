#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Get-WindowsDiscoveryProbes.ps1')
}

Describe 'Get-WindowsDiscoveryProbe' -Tag 'lib' {
    BeforeAll {
        Mock Get-Command { $null }
        Mock Get-ChildItem { @() }
        Mock Get-ScheduledTask { @() }
        Mock Get-CimInstance { @() }
    }

    It 'returns an array of probe records' {
        $probes = @(Get-WindowsDiscoveryProbe)
        $probes.Count | Should -BeGreaterOrEqual 8
    }

    It 'every record has the documented shape' {
        $probes = @(Get-WindowsDiscoveryProbe)
        foreach ($p in $probes) {
            $p.PSObject.Properties.Name | Should -Contain 'dimension'
            $p.PSObject.Properties.Name | Should -Contain 'detected'
            $p.PSObject.Properties.Name | Should -Contain 'suggested_check_id'
            $p.PSObject.Properties.Name | Should -Contain 'rationale'
            $p.PSObject.Properties.Name | Should -Contain 'straightforward'
        }
    }

    It 'reports detected=$false for absent tools' {
        $probes = @(Get-WindowsDiscoveryProbe)
        $docker = $probes | Where-Object dimension -EQ 'Docker Desktop'
        $docker.detected | Should -BeFalse
        $wsl = $probes | Where-Object dimension -EQ 'WSL distros'
        $wsl.detected | Should -BeFalse
    }

    It 'includes .NET, Node, Python, Docker, WSL, Cert-store, Scheduled-tasks, Reliability' {
        $probes = @(Get-WindowsDiscoveryProbe)
        $dimensions = $probes | ForEach-Object dimension
        $dimensions | Should -Contain '.NET SDK'
        $dimensions | Should -Contain 'Node.js runtime'
        $dimensions | Should -Contain 'Python runtime'
        $dimensions | Should -Contain 'Docker Desktop'
        $dimensions | Should -Contain 'WSL distros'
        $dimensions | Should -Contain 'User certificate store'
        $dimensions | Should -Contain 'Scheduled task failures'
        $dimensions | Should -Contain 'Reliability Monitor data'
    }
}
