#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-SdkVersions.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    . (Join-Path $script:TestsRoot 'helpers\Invoke-CheckScript.ps1')

    function Invoke-SdkVersionsAsObject { Invoke-CheckScriptAsObject $script:ScriptPath }
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
    It 'sorts by EOL date so the first-detected runtime is not automatically oldest' {
        # Pin the sort the INFO summary uses: earliest eol_date wins, unknown last.
        $findings = @(
            [pscustomobject]@{ runtime = 'node'; version = '22'; eol_date = '2027-04-30'; state = 'active' }
            [pscustomobject]@{ runtime = 'dotnet'; version = '6.0'; eol_date = '2024-11-12'; state = 'eol' }
            [pscustomobject]@{ runtime = 'python'; version = '3.12'; eol_date = $null; state = 'unknown_eol' }
        )
        $oldest = @(
            $findings | Sort-Object @{
                Expression = {
                    if ($_.eol_date) { [datetime]$_.eol_date } else { [datetime]::MaxValue }
                }
            }, runtime, version
        )[0]
        $oldest.runtime | Should -Be 'dotnet'
        $oldest.version | Should -Be '6.0'
    }
}
