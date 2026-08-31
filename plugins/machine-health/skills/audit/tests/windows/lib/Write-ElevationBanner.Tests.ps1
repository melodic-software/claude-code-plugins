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

    # Write-ElevationBanner writes via [Console]::Error.WriteLine, which
    # bypasses PowerShell's error stream, so `2>&1` captures nothing.
    # Swap in a StringWriter around the call to capture real stderr text.
    function Invoke-BannerCapture {
        param([Parameter(Mandatory)] [scriptblock] $Call)
        $writer = [System.IO.StringWriter]::new()
        $saved = [Console]::Error
        try {
            [Console]::SetError($writer)
            & $Call
        } finally {
            [Console]::SetError($saved)
        }
        return $writer.ToString()
    }
}

Describe 'Write-ElevationBanner' -Tag 'lib' {
    It 'emits the banner to stderr when non-elevated' {
        $err = Invoke-BannerCapture {
            Write-ElevationBanner -Elevated $false -HostName 'HOST' `
                -UserName 'DOMAIN\user' -OutputBase 'C:\out' `
                -SkillRoot 'C:\skill' -Matrix @(Get-ElevationMatrix)
        }
        $err | Should -Match 'NON-ELEVATED'
        $err | Should -Match ([regex]::Escape('Running as DOMAIN\user'))
        $err | Should -Match 'Suppress this banner with -SkipBanner'
    }

    It 'emits nothing when elevated' {
        $err = Invoke-BannerCapture {
            Write-ElevationBanner -Elevated $true -HostName 'HOST' `
                -UserName 'DOMAIN\user' -OutputBase 'C:\out' `
                -SkillRoot 'C:\skill' -Matrix @(Get-ElevationMatrix)
        }
        $err | Should -BeNullOrEmpty
    }

    It 'emits nothing when -Quiet even if non-elevated' {
        $err = Invoke-BannerCapture {
            Write-ElevationBanner -Elevated $false -HostName 'HOST' `
                -UserName 'DOMAIN\user' -OutputBase 'C:\out' `
                -SkillRoot 'C:\skill' -Matrix @(Get-ElevationMatrix) -Quiet
        }
        $err | Should -BeNullOrEmpty
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
