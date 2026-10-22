#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Write-ElevationBanner.ps1.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" `
        -LibScript 'Write-ElevationBanner.ps1', 'Get-ElevationMatrix.ps1'

    # [Console]::Error.WriteLine bypasses the error stream, so `2>&1` captures nothing;
    # swap in a StringWriter to capture real stderr text.
    function Invoke-BannerCapture {
        param(
            [Parameter(Mandatory)] [bool] $Elevated,
            [switch] $Quiet,
            [string[]] $Coverage = @()
        )
        $writer = [System.IO.StringWriter]::new()
        $saved = [Console]::Error
        try {
            [Console]::SetError($writer)
            Write-ElevationBanner -Elevated $Elevated -HostName 'HOST' `
                -UserName 'DOMAIN\user' -Matrix @(Get-ElevationMatrix) `
                -NonElevatedCoverage $Coverage -Quiet:$Quiet
        } finally {
            [Console]::SetError($saved)
        }
        return $writer.ToString()
    }
}

Describe 'Write-ElevationBanner' -Tag 'lib' {
    It 'emits the banner to stderr when non-elevated' {
        $err = Invoke-BannerCapture -Elevated $false
        $err | Should -Match 'NON-ELEVATED'
        $err | Should -Match ([regex]::Escape('Running as DOMAIN\user'))
        $err | Should -Match 'Suppress this banner with -SkipBanner'
    }

    It 'points to the session-driven elevated pass and prints no command to run' {
        $err = Invoke-BannerCapture -Elevated $false
        $err | Should -Match ([regex]::Escape(' To run elevated:'))
        $err | Should -Match 'Ask the session that ran this audit for the elevated pass'
        $err | Should -Match 'SHA-256'
        $err | Should -Not -Match 'Start-Transcript'
        $err | Should -Not -Match 'pwsh '
    }

    It 'lists each derived coverage label under Covered non-elevated' {
        $err = Invoke-BannerCapture -Elevated $false -Coverage @('disk-space', 'my-check [custom]')
        $err | Should -Match ([regex]::Escape(' Covered non-elevated:'))
        $err | Should -Match ([regex]::Escape('   - disk-space'))
        $err | Should -Match ([regex]::Escape('   - my-check [custom]'))
    }

    It 'omits the coverage section when the derived list is empty' {
        $err = Invoke-BannerCapture -Elevated $false
        $err | Should -Not -Match 'Covered non-elevated'
        $err | Should -Match 'Admin-only'
    }

    It 'emits nothing when elevated' {
        $err = Invoke-BannerCapture -Elevated $true
        $err | Should -BeNullOrEmpty
    }

    It 'emits nothing when -Quiet even if non-elevated' {
        $err = Invoke-BannerCapture -Elevated $false -Quiet
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
        $md | Should -Match 'elevated pass'
        $md | Should -Not -Match 'transcript'
    }

    It 'returns a placeholder when matrix is empty' {
        $md = Get-ElevationCoverageMarkdown -Elevated $false -Matrix @()
        $md | Should -Match 'No admin-gated checks registered'
    }
}
