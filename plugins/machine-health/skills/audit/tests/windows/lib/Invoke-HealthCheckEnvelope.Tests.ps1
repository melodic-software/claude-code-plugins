#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Write-HealthResult.ps1'
    $script:Envelope = Join-Path $script:LibRoot 'Invoke-HealthCheckEnvelope.ps1'
}

Describe 'Invoke-HealthCheckEnvelope' -Tag 'lib' {
    It 'emits one JSON result and stamps the duration' {
        $id = 'envelope-probe'
        $category = 'network'
        $commands = @('noop')
        $FailureSummary = 'probe failed.'
        $PassThru = $false
        $CheckBody = {
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'OK' -Summary 'ok' -Commands $commands
        }
        $json = . $script:Envelope
        $parsed = $json | ConvertFrom-Json
        $parsed.id | Should -Be 'envelope-probe'
        $parsed.severity | Should -Be 'OK'
        $parsed.duration_ms | Should -BeOfType [long]
        $parsed.ran_successfully | Should -BeTrue
    }

    It 'turns a thrown body into the UNKNOWN fallback' {
        $id = 'envelope-probe'
        $category = 'network'
        $commands = @('noop')
        $FailureSummary = 'probe failed.'
        $PassThru = $false
        $FailureNeedsAdmin = $true
        $FailureAdminFields = @('secret')
        $CheckBody = { throw 'boom' }
        $json = . $script:Envelope
        $parsed = $json | ConvertFrom-Json
        $parsed.severity | Should -Be 'UNKNOWN'
        $parsed.ran_successfully | Should -BeFalse
        $parsed.summary | Should -Be 'probe failed.'
        $parsed.error | Should -Be 'boom'
        $parsed.needs_admin | Should -BeTrue
        $parsed.detail.admin_fields | Should -Be @('secret')
    }

    It 'resolves a mock through the check scope' {
        function Get-EnvelopeProbe { 'real' }
        Mock Get-EnvelopeProbe { 'mocked' }
        $id = 'envelope-probe'
        $category = 'network'
        $commands = @('noop')
        $FailureSummary = 'probe failed.'
        $PassThru = $false
        $CheckBody = {
            $seen = Get-EnvelopeProbe
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'OK' -Summary $seen -Commands $commands
        }
        $json = . $script:Envelope
        ($json | ConvertFrom-Json).summary | Should -Be 'mocked'
    }

    It 'lets the body read the running stopwatch' {
        $id = 'envelope-probe'
        $category = 'network'
        $commands = @('noop')
        $FailureSummary = 'probe failed.'
        $PassThru = $false
        $CheckBody = {
            $running = $sw.IsRunning
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'OK' -Summary "$running" -Commands $commands
        }
        $json = . $script:Envelope
        ($json | ConvertFrom-Json).summary | Should -Be 'True'
    }

    It 'stamps the object and does not write it when PassThru is set' {
        $id = 'envelope-probe'
        $category = 'network'
        $commands = @('noop')
        $FailureSummary = 'probe failed.'
        $PassThru = $true
        $CheckBody = {
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'INFO' -Summary 'passthru' -Commands $commands
        }
        $written = . $script:Envelope
        $written | Should -BeNullOrEmpty
        $result.summary | Should -Be 'passthru'
        $result.duration_ms | Should -BeOfType [int]
    }

    It 'is the only envelope in the check family' {
        $checksDir = Join-Path $script:LibRoot '..\checks'
        $checks = @(Get-ChildItem -LiteralPath $checksDir -Filter '*.ps1' -File)
        $checks.Count | Should -BeGreaterThan 15
        foreach ($check in $checks) {
            $text = Get-Content -LiteralPath $check.FullName -Raw
            $text | Should -Not -Match 'Stopwatch\]::StartNew' -Because $check.Name
            $text | Should -Not -Match 'New-HealthFailureResult' -Because $check.Name
            $text | Should -Not -Match 'Complete-HealthCheck' -Because $check.Name
            $text | Should -Not -Match 'Write-HealthResult -Human' -Because $check.Name
        }
    }
}
