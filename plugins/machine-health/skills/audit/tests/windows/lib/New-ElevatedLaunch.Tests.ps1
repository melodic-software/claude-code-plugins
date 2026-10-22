#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-ElevatedLaunch.ps1. The launch string runs
here exactly as the elevated pass runs it, one string through Start-Process
-ArgumentList into pwsh, minus -Verb RunAs, against a stub orchestrator that
prints the parameters it received.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-ElevatedLaunch.ps1', 'Write-ElevatedResult.ps1'

    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:SavedOneDrive = $env:OneDrive

    # Run the launch string in a child pwsh; returns its exit code and the parameters
    # the stub orchestrator wrote to bound.json (UTF-8, so no console code page alters
    # them), or $null when the stub did not run.
    function Invoke-LaunchString {
        param([string] $ArgumentString, [string] $WorkDir, [string] $BoundPath)
        $stdout = Join-Path $WorkDir "stdout-$([guid]::NewGuid()).txt"
        $stderr = Join-Path $WorkDir "stderr-$([guid]::NewGuid()).txt"
        $process = Start-Process -FilePath $script:Pwsh -ArgumentList $ArgumentString -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $process.WaitForExit(60000)) {
            $process.Kill($true)
            throw 'The launch string did not finish within 60 s.'
        }
        $bound = if (Test-Path -LiteralPath $BoundPath) { Get-Content -LiteralPath $BoundPath -Raw -Encoding utf8 | ConvertFrom-Json }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Bound = $bound }
    }
}

AfterAll {
    $env:OneDrive = $script:SavedOneDrive
}

Describe 'New-ElevatedLaunch' -Tag 'lib' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:work = Join-Path $root 'work'
        $script:skillRoot = Join-Path $root 'skill root'
        $orchestratorDir = Join-Path $script:skillRoot 'scripts\windows'
        New-Item -ItemType Directory -Path $script:work, $orchestratorDir | Out-Null
        $script:boundPath = Join-Path $orchestratorDir 'bound.json'
        Set-Content -LiteralPath (Join-Path $orchestratorDir 'Invoke-MachineHealthCheck.ps1') -Encoding utf8 -Value @'
param($OutputBase, $StateBase, $RunMode, [switch] $SkipBanner, $ResultPath, $ResultFileId)
[pscustomobject]@{
    OutputBase = $OutputBase; StateBase = $StateBase; RunMode = $RunMode; SkipBanner = $SkipBanner.IsPresent
    ResultPath = $ResultPath; ResultFileId = $ResultFileId
} | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bound.json') -Encoding utf8
'@
        # A space, an apostrophe and a typographic quote: each must survive both quoting layers.
        $script:stateBase = Join-Path $root "state base's"
        $script:outputBase = Join-Path $root "reports $([char]0x2019)out"
    }

    It 'pre-creates an empty result file under logs and returns an ID Write-ElevatedResult accepts' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $launch.ResultPath | Should -BeLike "$script:stateBase\logs\elevated-result-*.json"
        (Split-Path -Leaf $launch.ResultPath) | Should -Match '^elevated-result-\d{4}-\d{2}-\d{2}T\d{9}Z\.json$'
        (Get-Item -LiteralPath $launch.ResultPath).Length | Should -Be 0
        $launch.ResultFileId | Should -Match '^[0-9A-F]{8}-[0-9A-F]{16}$'
        { Write-ElevatedResult -Path $launch.ResultPath -FileId $launch.ResultFileId -Results @() } | Should -Not -Throw
        { Write-ElevatedResult -Path $launch.ResultPath -FileId '00000000-0000000000000000' -Results @() } |
            Should -Throw '*file ID*'
    }

    It 'writes one command, without a byte order mark, whose SHA-256 is the returned hash' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $launch.ScriptSha256 | Should -BeExactly (Get-FileHash -LiteralPath $launch.ScriptPath -Algorithm SHA256).Hash
        (Split-Path -Leaf $launch.ScriptPath) | Should -Match '^elevated-run-\d{4}-\d{2}-\d{2}T\d{9}Z\.ps1$'
        $bytes = [System.IO.File]::ReadAllBytes($launch.ScriptPath)
        $bytes[0] | Should -Be ([byte][char]'&')
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        @($text -split "`n").Count | Should -Be 1
        $text | Should -BeLike "*-RunMode on-demand -SkipBanner -ResultPath *-ResultFileId '$($launch.ResultFileId)'"
        $text | Should -Not -Match 'DryRun|Transcript'
        $launch.ArgumentString | Should -BeLike "-NoProfile -Command ""*'$($launch.ScriptSha256)'*"""
    }

    It 'round-trips a state path holding a space and quotes through Start-Process and pwsh -Command' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $run = Invoke-LaunchString -ArgumentString $launch.ArgumentString -WorkDir $script:work -BoundPath $script:boundPath

        $run.ExitCode | Should -Be 0
        $bound = $run.Bound
        $bound.StateBase | Should -BeExactly $script:stateBase
        $bound.OutputBase | Should -BeExactly $script:outputBase
        $bound.ResultPath | Should -BeExactly $launch.ResultPath
        $bound.ResultFileId | Should -BeExactly $launch.ResultFileId
        $bound.RunMode | Should -BeExactly 'on-demand'
        $bound.SkipBanner | Should -BeTrue
    }

    It 'exits 3 without running the script when it was edited after the hash' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot
        Add-Content -LiteralPath $launch.ScriptPath -Value '; ''tampered''' -NoNewline

        $run = Invoke-LaunchString -ArgumentString $launch.ArgumentString -WorkDir $script:work -BoundPath $script:boundPath

        $run.ExitCode | Should -Be 3
        $run.Bound | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:boundPath | Should -BeFalse
    }

    It 'refuses a state folder under a OneDrive root and creates nothing there' {
        $env:OneDrive = Split-Path -Parent $script:stateBase
        try {
            { New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot } |
                Should -Throw '*cloud sync root*'
        } finally {
            $env:OneDrive = $script:SavedOneDrive
        }
        Test-Path -LiteralPath $script:stateBase | Should -BeFalse
    }
}
