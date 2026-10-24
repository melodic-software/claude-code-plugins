#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for skills/setup/scripts/Install-MonthlyRun.ps1, which setup's schedule
step uses to copy the monthly wrapper, and its check step uses to tell whether
that copy is current.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1"
    $script:SetupRoot = Join-Path (Split-Path -Parent $script:SkillRoot) 'setup'
    . (Join-Path $script:SetupRoot 'scripts\Install-MonthlyRun.ps1')
    $script:Template = Join-Path $script:SetupRoot 'templates\monthly-run.ps1'
}

Describe 'Install-MonthlyRun and Test-MonthlyRunCurrent' -Tag 'lib' {
    BeforeEach {
        $script:Base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Installed = Install-MonthlyRun -StateBase $script:Base
    }

    It 'copies the wrapper template unchanged into the scheduler folder under the state root' {
        $script:Installed.WrapperPath | Should -Be (Join-Path $script:Base 'scheduler\monthly-run.ps1')
        [System.IO.File]::ReadAllText($script:Installed.WrapperPath) | Should -BeExactly ([System.IO.File]::ReadAllText($script:Template))
    }

    It 'removes the settings file an earlier build installed beside the wrapper' {
        $old = Join-Path $script:Base 'scheduler\scheduled-settings.json'
        Set-Content -LiteralPath $old -Value '{}'
        Install-MonthlyRun -StateBase $script:Base | Out-Null
        $old | Should -Not -Exist
    }

    It 'reports a fresh copy as current' {
        (Test-MonthlyRunCurrent -StateBase $script:Base).WrapperCurrent | Should -BeTrue
    }

    It 'reports the copy stale once it differs from the template, and missing as not current' {
        Add-Content -LiteralPath $script:Installed.WrapperPath -Value '# older build'
        (Test-MonthlyRunCurrent -StateBase $script:Base).WrapperCurrent | Should -BeFalse
        Remove-Item -LiteralPath $script:Installed.WrapperPath
        (Test-MonthlyRunCurrent -StateBase $script:Base).WrapperCurrent | Should -BeFalse
    }
}
