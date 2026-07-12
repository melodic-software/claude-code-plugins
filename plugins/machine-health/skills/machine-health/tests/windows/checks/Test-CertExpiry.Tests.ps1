#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-CertExpiry.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')

    function Invoke-CertExpiryAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }

    function New-MockCertEntry {
        param(
            [string] $Subject = 'CN=Mock',
            [string] $Issuer = 'CN=Mock CA',
            [int] $DaysFromNow = 365,
            [string] $Thumbprint = '0000000000000000000000000000000000000000'
        )
        [pscustomobject]@{
            Subject    = $Subject
            Issuer     = $Issuer
            NotAfter   = (Get-Date).AddDays($DaysFromNow)
            Thumbprint = $Thumbprint
        }
    }
}

Describe 'Test-CertExpiry -- baseline' -Tag 'check' {
    It 'emits a schema-valid CheckResult with no certs' {
        Mock Get-ChildItem { @() }
        $result = Invoke-CertExpiryAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'cert-expiry'
        $result.severity | Should -Be 'OK'
    }

    It 'reports OK when all certs are >90 days out' {
        Mock Get-ChildItem { @(New-MockCertEntry -DaysFromNow 365) }
        $result = Invoke-CertExpiryAsObject
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-CertExpiry -- severity rubric' -Tag 'check' {
    It 'reports INFO when a cert expires in 31-90 days' {
        Mock Get-ChildItem { @(New-MockCertEntry -DaysFromNow 45) }
        $result = Invoke-CertExpiryAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.info_count | Should -Be 1
    }

    It 'reports WARN when a cert expires in 8-30 days' {
        Mock Get-ChildItem { @(New-MockCertEntry -DaysFromNow 15) }
        $result = Invoke-CertExpiryAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.warn_count | Should -Be 1
    }

    It 'reports CRIT when a cert expires in <=7 days' {
        Mock Get-ChildItem { @(New-MockCertEntry -DaysFromNow 3) }
        $result = Invoke-CertExpiryAsObject
        $result.severity | Should -Be 'CRIT'
        $result.detail.crit_count | Should -Be 1
    }

    It 'reports CRIT when a cert is already expired' {
        Mock Get-ChildItem { @(New-MockCertEntry -DaysFromNow -10) }
        $result = Invoke-CertExpiryAsObject
        $result.severity | Should -Be 'CRIT'
        $result.detail.expired_count | Should -Be 1
    }

    It 'filters out DO_NOT_TRUST and localhost certs' {
        Mock Get-ChildItem {
            @(
                New-MockCertEntry -Subject 'CN=DO_NOT_TRUST_FiddlerRoot' -DaysFromNow 2
                New-MockCertEntry -Subject 'CN=localhost' -DaysFromNow 2
                New-MockCertEntry -Subject 'CN=Real' -DaysFromNow 365
            )
        }
        $result = Invoke-CertExpiryAsObject
        $result.severity | Should -Be 'OK'
        $result.detail.total_count | Should -Be 1
    }
}
