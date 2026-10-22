#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-RemediationId.ps1 -- remediation ids derived
from the shipped remediation scripts.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-RemediationId.ps1'
}

Describe 'Get-RemediationId' -Tag 'lib' {
    It 'returns the two shipped remediation ids' {
        # The ids remediation-policy.md and approvals.schema.json document.
        Get-RemediationId | Should -Be @('clear-temp-files', 'restart-stopped-service')
    }

    It 'matches the id each shipped remediation reports in its attempt records' {
        $dir = Join-Path $script:SkillRoot 'scripts\windows\remediations'
        foreach ($file in Get-ChildItem -LiteralPath $dir -Filter '*.ps1') {
            $declared = [regex]::Match((Get-Content -LiteralPath $file.FullName -Raw), "\bid\s*=\s*'([a-z-]+)'").Groups[1].Value
            Get-RemediationId | Should -Contain $declared -Because $file.Name
        }
    }

    It 'turns a PascalCase script name into a kebab-case id' {
        New-Item -ItemType File -Path (Join-Path $TestDrive 'Reset-DnsCache.ps1') | Out-Null
        Get-RemediationId -RemediationsDir $TestDrive | Should -Be @('reset-dns-cache')
    }
}
