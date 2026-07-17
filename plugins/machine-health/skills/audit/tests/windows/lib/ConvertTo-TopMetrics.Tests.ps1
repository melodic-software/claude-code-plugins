#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'ConvertTo-TopMetrics.ps1')

    function New-CheckStub {
        param(
            [string] $Id = 'foo',
            $Detail = @{}
        )
        [pscustomobject]@{ id = $Id; detail = $Detail }
    }
}

Describe 'ConvertTo-TopMetric' -Tag 'lib' {
    It 'captures scalar int/bool/string/double values from a hashtable detail' {
        $check = New-CheckStub -Id 'disk-space' -Detail @{
            used_pct = 87
            free_gb  = 59.4
            healthy  = $true
            label    = 'C:'
            nested   = @{ subkey = 1 }
            array    = @(1, 2, 3)
            null_val = $null
        }

        $m = ConvertTo-TopMetric -CheckResults @($check)
        $m['disk-space.used_pct'] | Should -Be 87
        $m['disk-space.free_gb'] | Should -Be 59.4
        $m['disk-space.healthy'] | Should -BeTrue
        $m['disk-space.label'] | Should -Be 'C:'
        $m.Contains('disk-space.nested') | Should -BeFalse
        $m.Contains('disk-space.array') | Should -BeFalse
        $m.Contains('disk-space.null_val') | Should -BeFalse
    }

    It 'captures scalar values from a PSCustomObject detail (post-JSON shape)' {
        $check = New-CheckStub -Id 'battery' -Detail ([pscustomobject]@{
                has_battery       = $true
                full_capacity_pct = 78.2
            })
        $m = ConvertTo-TopMetric -CheckResults @($check)
        $m['battery.has_battery'] | Should -BeTrue
        $m['battery.full_capacity_pct'] | Should -Be 78.2
    }

    It 'handles empty input' {
        $m = ConvertTo-TopMetric -CheckResults @()
        $m.Count | Should -Be 0
    }

    It 'skips checks without detail' {
        $check = [pscustomobject]@{ id = 'x'; detail = $null }
        $m = ConvertTo-TopMetric -CheckResults @($check)
        $m.Count | Should -Be 0
    }
}
