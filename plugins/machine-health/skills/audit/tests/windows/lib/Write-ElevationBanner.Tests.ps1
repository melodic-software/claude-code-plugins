#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Write-ElevationBanner.ps1.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Write-ElevationBanner.ps1')
    . (Join-Path $script:LibRoot 'Get-ElevationMatrix.ps1')
}

Describe 'Write-ElevationBanner' -Tag 'lib' {
    It 'emits nothing when elevated' {
        $err = & {
            Write-ElevationBanner -Elevated $true -HostName 'HOST' `
                -UserName 'DOMAIN\user' -OutputBase 'C:\out' `
                -SkillRoot 'C:\skill' -Matrix @(Get-ElevationMatrix)
        } 2>&1
        # Pester captures stderr. Expect no banner output.
        @($err | Where-Object { $_ -match '=' }).Count | Should -Be 0
    }

    It 'emits nothing when -Quiet even if non-elevated' {
        $err = & {
            Write-ElevationBanner -Elevated $false -HostName 'HOST' `
                -UserName 'DOMAIN\user' -OutputBase 'C:\out' `
                -SkillRoot 'C:\skill' -Matrix @(Get-ElevationMatrix) -Quiet
        } 2>&1
        @($err | Where-Object { $_ -match 'NON-ELEVATED' }).Count | Should -Be 0
    }
}

Describe 'Get-ElevationCoverageMarkdown' -Tag 'lib' {
    It 'returns terse line when elevated' {
        $md = Get-ElevationCoverageMarkdown -Elevated $true -Matrix @(Get-ElevationMatrix)
        $md | Should -Match 'Elevated run'
    }

    It 'returns a details block enumerating capabilities when non-elevated' {
        $md = Get-ElevationCoverageMarkdown -Elevated $false -Matrix @(Get-ElevationMatrix)
        $md | Should -Match '<details>'
        $md | Should -Match 'admin-gated capabilities skipped'
        $md | Should -Match 'SMART disk reliability counters'
    }

    It 'returns a placeholder when matrix is empty' {
        $md = Get-ElevationCoverageMarkdown -Elevated $false -Matrix @()
        $md | Should -Match 'No admin-gated checks registered'
    }
}
