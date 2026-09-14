#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Invoke-AllowlistedWeb.ps1.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Invoke-AllowlistedWeb.ps1' -MockHelpers
}

Describe 'Invoke-AllowlistedWeb -- allowlist' -Tag 'lib' {
    It 'allows a host on the exact-match allowlist' {
        Test-EgressHostAllowed -HostName 'www.cisa.gov' | Should -BeTrue
    }

    It 'allows a host matching a leading-wildcard pattern' {
        Test-EgressHostAllowed -HostName 'download.update.microsoft.com' | Should -BeTrue
    }

    It 'is case-insensitive' {
        Test-EgressHostAllowed -HostName 'WWW.CISA.GOV' | Should -BeTrue
    }

    It 'rejects a host not on the allowlist' {
        Test-EgressHostAllowed -HostName 'example.com' | Should -BeFalse
    }

    It 'does not match a false-prefix collision (microsoft.com vs update.microsoft.com)' {
        Test-EgressHostAllowed -HostName 'microsoft.com' | Should -BeFalse
    }
}

Describe 'Invoke-AllowlistedWeb -- HTTP call' -Tag 'lib' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-egress'
        $script:logPath = Join-Path $script:tmpDir 'run.log'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    It 'calls Invoke-WebRequest and logs a GET line when host is allowed' {
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }

        $r = Invoke-AllowlistedWeb -Uri 'https://www.cisa.gov/feed.json' -LogPath $script:logPath
        $r.StatusCode | Should -Be 200

        $log = Get-Content -LiteralPath $script:logPath -Raw
        $log | Should -Match 'egress GET'
        $log | Should -Match 'cisa\.gov'
    }

    It 'refuses to call for a denied host and logs DENY' {
        Mock Invoke-WebRequest { throw 'should never be called' }

        { Invoke-AllowlistedWeb -Uri 'https://evil.example/payload' -LogPath $script:logPath } |
            Should -Throw -ExpectedMessage '*not on egress allowlist*'

        Should -Invoke Invoke-WebRequest -Times 0
        $log = Get-Content -LiteralPath $script:logPath -Raw
        $log | Should -Match 'egress DENY'
    }

    It 'logs FAIL and re-throws when Invoke-WebRequest throws' {
        Mock Invoke-WebRequest { throw 'TLS handshake failed' }

        { Invoke-AllowlistedWeb -Uri 'https://www.cisa.gov/x' -LogPath $script:logPath } |
            Should -Throw -ExpectedMessage '*TLS handshake failed*'

        $log = Get-Content -LiteralPath $script:logPath -Raw
        $log | Should -Match 'egress FAIL'
        $log | Should -Match 'TLS handshake failed'
    }
}

Describe 'Invoke-AllowlistedWeb -- Read-EgressLog' -Tag 'lib' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-egress-log'
        $script:logPath = Join-Path $script:tmpDir 'run.log'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    It 'returns @() when log does not exist' {
        $entries = Read-EgressLog -LogPath $script:logPath
        $entries | Should -BeNullOrEmpty
    }

    It 'parses GET, FAIL, and DENY lines' {
        $lines = @(
            '2026-04-23T00:00:00-04:00 egress GET https://www.cisa.gov/a.json'
            '2026-04-23T00:00:01-04:00 egress FAIL https://www.cisa.gov/b.json - timeout'
            '2026-04-23T00:00:02-04:00 egress DENY https://bad.example/x - not on allowlist'
            'random line that is not egress'
        )
        Set-Content -LiteralPath $script:logPath -Value $lines -Encoding utf8

        $entries = @(Read-EgressLog -LogPath $script:logPath)
        $entries.Count | Should -Be 3
        $entries[0].kind | Should -Be 'GET'
        $entries[1].kind | Should -Be 'FAIL'
        $entries[1].message | Should -Be 'timeout'
        $entries[2].kind | Should -Be 'DENY'
    }
}
