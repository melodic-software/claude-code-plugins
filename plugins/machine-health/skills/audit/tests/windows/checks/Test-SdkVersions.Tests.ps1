#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-SdkVersions' -AsObject 'Invoke-SdkVersionsAsObject'
}

Describe 'Test-SdkVersions -- baseline' -Tag 'check' {
    It 'emits a schema-valid CheckResult when no SDKs are on PATH' {
        # Native SDK commands cannot be mocked reliably. Stub Get-Command to
        # report absence; the script's guard path takes over.
        Mock Get-Command {
            param($Name)
            if ($Name -in @('dotnet', 'node', 'python', 'python3')) { return $null }
            return (Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue)
        }
        $result = Invoke-SdkVersionsAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'sdk-versions'
        $result.severity | Should -Be 'OK'
        $result.detail.runtimes_detected | Should -Be 0
    }
}

Describe 'Test-SdkVersions -- oldest label' -Tag 'check' {
    BeforeAll {
        # `& $Path` runs the check in its own script scope, so a test-script
        # function is invisible. Global shadows are what `& dotnet` resolves.
        function global:dotnet { $args | Out-Null; '8.0.100 [C:\sdk]' }
        function global:node { $args | Out-Null; 'v22.0.0' }
    }
    AfterAll {
        Remove-Item function:global:dotnet -ErrorAction SilentlyContinue
        Remove-Item function:global:node -ErrorAction SilentlyContinue
    }

    It 'labels oldest by EOL date, not detection order' {
        # INFO is only reachable with no eol / eol_soon findings. First-detected
        # is always dotnet, so the table gives node the earlier (still-active)
        # EOL. A `$findings[0]` regression would name dotnet 8.0.
        Mock Get-Command {
            param($Name)
            if ($Name -eq 'dotnet' -or $Name -eq 'node') {
                return [pscustomobject]@{ Name = $Name; Source = $Name }
            }
            if ($Name -in @('python', 'python3')) { return $null }
            return (Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue)
        }
        $nodeEol = (Get-Date).AddYears(5).ToString('yyyy-MM-dd')
        $dotnetEol = (Get-Date).AddYears(8).ToString('yyyy-MM-dd')
        $eolJson = (@{
                dotnet = @{ eol = @{ '8.0' = $dotnetEol } }
                node   = @{ eol = @{ '22' = $nodeEol } }
                python = @{ eol = @{} }
            } | ConvertTo-Json -Compress -Depth 5)
        Mock Get-Content { $eolJson } -ParameterFilter { $LiteralPath -match 'sdk-eol-table\.json$' }
        $result = Invoke-SdkVersionsAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'INFO'
        $result.summary | Should -Match 'oldest: node 22'
        $result.summary | Should -Not -Match 'oldest: dotnet'
    }
}
