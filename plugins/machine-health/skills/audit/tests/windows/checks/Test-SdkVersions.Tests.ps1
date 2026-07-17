#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-SdkVersions.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')

    function Invoke-SdkVersionsAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
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
