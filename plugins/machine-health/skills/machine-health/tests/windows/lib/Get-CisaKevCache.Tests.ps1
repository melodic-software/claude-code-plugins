#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-CisaKevCache.ps1.

.DESCRIPTION
The previous 32-byte size gate failed to detect the checked-in 238-byte seed
stub, so the cache never refreshed on first run. These tests pin the new
content-based detection (empty vulnerabilities array triggers refresh) and the
atomic-rename fetch path, while keeping fetch side-effects isolated via temp
directories and Pester mocks.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Get-CisaKevCache.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force
}

Describe 'Get-CisaKevCache' -Tag 'lib' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-kev'
        $script:cachePath = Join-Path $script:tmpDir 'cisa-kev.json'
        $script:logPath = Join-Path $script:tmpDir 'run.log'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    Context 'refresh decisions' {
        It 'fetches when the cache file is missing' {
            Mock Invoke-WebRequest {
                $payload = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-0001' }) } | ConvertTo-Json
                Set-Content -LiteralPath $OutFile -Value $payload -Encoding utf8
            } -ParameterFilter { $OutFile -like '*.download' }

            $result = Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath
            $result.vulnerabilities.Count | Should -Be 1
            $result.vulnerabilities[0].cveID | Should -Be 'CVE-2024-0001'
            Should -Invoke Invoke-WebRequest -Times 1
        }

        It 'fetches when the cache is the checked-in seed stub (empty vulnerabilities)' {
            $stub = '{"_comment":"placeholder","vulnerabilities":[]}'
            Set-Content -LiteralPath $script:cachePath -Value $stub -Encoding utf8

            Mock Invoke-WebRequest {
                $payload = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-0002' }) } | ConvertTo-Json
                Set-Content -LiteralPath $OutFile -Value $payload -Encoding utf8
            } -ParameterFilter { $OutFile -like '*.download' }

            $result = Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath
            $result.vulnerabilities.Count | Should -Be 1
            Should -Invoke Invoke-WebRequest -Times 1
        }

        It 'fetches when the cache is older than MaxAgeDays' {
            $fresh = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-0003' }) } | ConvertTo-Json
            Set-Content -LiteralPath $script:cachePath -Value $fresh -Encoding utf8
            (Get-Item -LiteralPath $script:cachePath).LastWriteTime = (Get-Date).AddDays(-10)

            Mock Invoke-WebRequest {
                $payload = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-0099' }) } | ConvertTo-Json
                Set-Content -LiteralPath $OutFile -Value $payload -Encoding utf8
            } -ParameterFilter { $OutFile -like '*.download' }

            $result = Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath -MaxAgeDays 7
            $result.vulnerabilities[0].cveID | Should -Be 'CVE-2024-0099'
            Should -Invoke Invoke-WebRequest -Times 1
        }

        It 'skips fetch when cache is fresh with content' {
            $fresh = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-0004' }) } | ConvertTo-Json
            Set-Content -LiteralPath $script:cachePath -Value $fresh -Encoding utf8

            Mock Invoke-WebRequest { }

            $result = Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath -MaxAgeDays 7
            $result.vulnerabilities[0].cveID | Should -Be 'CVE-2024-0004'
            Should -Invoke Invoke-WebRequest -Times 0
        }

        It 'fetches when -ForceRefresh is passed regardless of cache state' {
            $fresh = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-0005' }) } | ConvertTo-Json
            Set-Content -LiteralPath $script:cachePath -Value $fresh -Encoding utf8

            Mock Invoke-WebRequest {
                $payload = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-9999' }) } | ConvertTo-Json
                Set-Content -LiteralPath $OutFile -Value $payload -Encoding utf8
            } -ParameterFilter { $OutFile -like '*.download' }

            $result = Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath -ForceRefresh
            $result.vulnerabilities[0].cveID | Should -Be 'CVE-2024-9999'
            Should -Invoke Invoke-WebRequest -Times 1
        }
    }

    Context 'fetch failure handling' {
        It 'returns the prior cache when fetch throws, without clobbering' {
            $prior = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-PRIOR' }) } | ConvertTo-Json
            Set-Content -LiteralPath $script:cachePath -Value $prior -Encoding utf8
            (Get-Item -LiteralPath $script:cachePath).LastWriteTime = (Get-Date).AddDays(-10)

            Mock Invoke-WebRequest { throw 'network down' }

            $result = Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath `
                -MaxAgeDays 7 -WarningAction SilentlyContinue

            $result.vulnerabilities[0].cveID | Should -Be 'CVE-2024-PRIOR'
            Get-Content -LiteralPath $script:cachePath -Raw | Should -Match 'CVE-2024-PRIOR'
        }

        It 'returns an empty vulnerabilities array when cache missing and fetch fails' {
            Mock Invoke-WebRequest { throw 'DNS lookup failed' }

            $result = Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath `
                -WarningAction SilentlyContinue

            $result | Should -Not -BeNullOrEmpty
            @($result.vulnerabilities).Count | Should -Be 0
        }

        It 'does not leave a temp download file behind on failure' {
            Mock Invoke-WebRequest {
                Set-Content -LiteralPath $OutFile -Value 'garbage' -Encoding utf8
            } -ParameterFilter { $OutFile -like '*.download' }

            Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath `
                -WarningAction SilentlyContinue | Out-Null

            Test-Path -LiteralPath "$($script:cachePath).download" | Should -BeFalse
        }

        It 'does not overwrite a good cache when the download is unparsable' {
            $prior = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-KEEP' }) } | ConvertTo-Json
            Set-Content -LiteralPath $script:cachePath -Value $prior -Encoding utf8

            Mock Invoke-WebRequest {
                Set-Content -LiteralPath $OutFile -Value '{broken json' -Encoding utf8
            } -ParameterFilter { $OutFile -like '*.download' }

            Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath `
                -ForceRefresh -WarningAction SilentlyContinue | Out-Null

            Get-Content -LiteralPath $script:cachePath -Raw | Should -Match 'CVE-2024-KEEP'
        }
    }

    Context 'egress logging' {
        It 'appends a GET line to the log when a refresh is attempted' {
            Mock Invoke-WebRequest {
                $payload = @{ vulnerabilities = @(@{ cveID = 'CVE-2024-0006' }) } | ConvertTo-Json
                Set-Content -LiteralPath $OutFile -Value $payload -Encoding utf8
            } -ParameterFilter { $OutFile -like '*.download' }

            Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath | Out-Null

            $logContent = Get-Content -LiteralPath $script:logPath -Raw
            $logContent | Should -Match 'egress GET'
            $logContent | Should -Match 'cisa\.gov'
        }

        It 'appends a FAIL line when fetch throws' {
            Mock Invoke-WebRequest { throw 'TLS handshake failed' }

            Get-CisaKevCache -CachePath $script:cachePath -LogPath $script:logPath `
                -WarningAction SilentlyContinue | Out-Null

            $logContent = Get-Content -LiteralPath $script:logPath -Raw
            $logContent | Should -Match 'egress FAIL'
            $logContent | Should -Match 'TLS handshake failed'
        }
    }
}
