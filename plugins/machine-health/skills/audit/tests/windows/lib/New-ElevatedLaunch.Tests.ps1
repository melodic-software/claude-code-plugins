#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-ElevatedLaunch.ps1 (New-, Get- and Start-ElevatedLaunch). The launch string runs
here exactly as the elevated pass runs it, one string through Start-Process
-ArgumentList into pwsh, minus -Verb RunAs, against a stub orchestrator that
prints the parameters it received.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-ElevatedLaunch.ps1', 'Write-ElevatedResult.ps1', 'Import-ElevatedResult.ps1'

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
        # Characters PowerShell would read as code outside a single-quoted literal.
        $script:root = $root
        $script:stateBase = Join-Path $root ('state base $x;&(%)' + [char]96 + 'n')
        $script:outputBase = Join-Path $root 'reports out; $(1)'
    }

    It 'pre-creates an empty result file under logs and returns an ID Write-ElevatedResult accepts' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $launch.ResultPath.StartsWith("$script:stateBase\logs\elevated-result-") | Should -BeTrue
        (Split-Path -Leaf $launch.ResultPath) | Should -Match '^elevated-result-\d{4}-\d{2}-\d{2}T\d{9}Z\.json$'
        (Get-Item -LiteralPath $launch.ResultPath).Length | Should -Be 0
        Test-FileIdFormat $launch.ResultFileId | Should -BeTrue
        { Write-ElevatedResult -Path $launch.ResultPath -FileId $launch.ResultFileId -Results @() } | Should -Not -Throw
        { Write-ElevatedResult -Path $launch.ResultPath -FileId '0000000000000000-00000000000000000000000000000000' -Results @() } |
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
        $text | Should -Not -Match 'DryRun|Transcript'
    }

    It 'writes a script that parses to the one intended command, every path a single-quoted constant' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $ast = [scriptblock]::Create([System.IO.File]::ReadAllText($launch.ScriptPath)).Ast
        @($ast.EndBlock.Statements).Count | Should -Be 1
        $command = $ast.EndBlock.Statements[0].PipelineElements[0]
        @($ast.EndBlock.Statements[0].PipelineElements).Count | Should -Be 1
        $command.InvocationOperator | Should -Be 'Ampersand'
        $elements = @($command.CommandElements)
        $elements[0].StringConstantType | Should -Be 'SingleQuoted'
        $elements[0].Value | Should -BeExactly (Join-Path $script:skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1')
        $bound = @{}
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $elements[$i] | Should -BeOfType ([System.Management.Automation.Language.CommandParameterAst])
            $name = $elements[$i].ParameterName
            if ($name -eq 'SkipBanner') { $bound[$name] = $true; continue }
            $i++
            $elements[$i] | Should -BeOfType ([System.Management.Automation.Language.StringConstantExpressionAst])
            $bound[$name] = $elements[$i].Value
        }
        @($bound.Keys | Sort-Object) | Should -Be @('OutputBase', 'ResultFileId', 'ResultPath', 'RunMode', 'SkipBanner', 'StateBase')
        $bound.StateBase | Should -BeExactly $script:stateBase
        $bound.OutputBase | Should -BeExactly $script:outputBase
        $bound.ResultPath | Should -BeExactly $launch.ResultPath
        $bound.ResultFileId | Should -BeExactly $launch.ResultFileId
        $bound.RunMode | Should -BeExactly 'on-demand'
    }

    It 'builds an argument string whose block is the hash check, then the run of the same bytes' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $launch.ArgumentString | Should -Match '^-NoProfile -Command "[^"]*"$'
        $block = $launch.ArgumentString.Substring('-NoProfile -Command "'.Length).TrimEnd('"')
        $ast = [scriptblock]::Create($block).Ast
        $statements = @($ast.EndBlock.Statements)
        $statements.Count | Should -Be 4
        $statements[0].Extent.Text | Should -BeExactly "`$b = [IO.File]::ReadAllBytes('$($launch.ScriptPath)')"
        $statements[1].Extent.Text | Should -BeLike "if (*-cne '$($launch.ScriptSha256)') { exit 3 }"
        $statements[2].Extent.Text | Should -BeExactly '& ([scriptblock]::Create([Text.UTF8Encoding]::new($false).GetString($b)))'
        $statements[3].Extent.Text | Should -BeExactly 'exit $LASTEXITCODE'
    }

    It 'round-trips the paths through Start-Process and pwsh -Command' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $run = Invoke-LaunchString -ArgumentString $launch.ArgumentString -WorkDir $script:work -BoundPath $script:boundPath

        $run.ExitCode | Should -Be 0
        $run.Bound.StateBase | Should -BeExactly $script:stateBase
        $run.Bound.OutputBase | Should -BeExactly $script:outputBase
        $run.Bound.ResultPath | Should -BeExactly $launch.ResultPath
        $run.Bound.ResultFileId | Should -BeExactly $launch.ResultFileId
        $run.Bound.RunMode | Should -BeExactly 'on-demand'
        $run.Bound.SkipBanner | Should -BeTrue
    }

    It 'exits 3 without running the script when it was edited after the hash' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot
        Add-Content -LiteralPath $launch.ScriptPath -Value '; ''tampered''' -NoNewline

        $run = Invoke-LaunchString -ArgumentString $launch.ArgumentString -WorkDir $script:work -BoundPath $script:boundPath

        $run.ExitCode | Should -Be 3
        $run.Bound | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:boundPath | Should -BeFalse
    }

    It 'refuses a <Case> in the <Which> and creates nothing' -ForEach @(
        @{ Case = 'right single quote'; Which = 'StateBase'; Char = [char]0x2019 }
        @{ Case = 'left single quote'; Which = 'StateBase'; Char = [char]0x2018 }
        @{ Case = 'low single quote'; Which = 'OutputBase'; Char = [char]0x201A }
        @{ Case = 'reversed single quote'; Which = 'OutputBase'; Char = [char]0x201B }
        @{ Case = 'apostrophe'; Which = 'StateBase'; Char = [char]0x27 }
        @{ Case = 'control character'; Which = 'StateBase'; Char = [char]0x1F }
    ) {
        $bad = Join-Path $script:root "st$($Char)); Write-Output INJECTED; #"
        $state = if ($Which -eq 'StateBase') { $bad } else { $script:stateBase }
        $output = if ($Which -eq 'OutputBase') { $bad } else { $script:outputBase }

        { New-ElevatedLaunch -OutputBase $output -StateBase $state -SkillRoot $script:skillRoot } |
            Should -Throw '*control character or a single quote*'
        Test-Path -LiteralPath $state | Should -BeFalse
    }

    It 'refuses a skill root holding a single quote' {
        $quotedRoot = Join-Path $script:root "skill$([char]0x2019)root"
        New-Item -ItemType Directory -Path (Join-Path $quotedRoot 'scripts\windows') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') `
            -Destination (Join-Path $quotedRoot 'scripts\windows')

        { New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $quotedRoot } |
            Should -Throw '*single quote*'
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

Describe 'Get-ElevatedLaunch' -Tag 'lib' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:skillRoot = Join-Path $root 'skill'
        New-Item -ItemType Directory -Path (Join-Path $script:skillRoot 'scripts\windows') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') -Value 'param()'
        $script:stateBase = Join-Path $root 'state'
        $script:launch = New-ElevatedLaunch -OutputBase (Join-Path $root 'out') -StateBase $script:stateBase -SkillRoot $script:skillRoot
    }

    It 'rebuilds the New-ElevatedLaunch record from the state root and the shown hash' {
        $found = Get-ElevatedLaunch -StateBase $script:stateBase -ScriptSha256 $script:launch.ScriptSha256

        foreach ($name in 'ScriptPath', 'ScriptSha256', 'ResultPath', 'ResultFileId', 'ArgumentString') {
            $found.$name | Should -BeExactly $script:launch.$name
        }
    }

    It 'finds nothing once the script no longer hashes to the shown value' {
        Add-Content -LiteralPath $script:launch.ScriptPath -Value ' ' -NoNewline

        { Get-ElevatedLaunch -StateBase $script:stateBase -ScriptSha256 $script:launch.ScriptSha256 } |
            Should -Throw '*No elevated-run script*'
    }
}

Describe 'Start-ElevatedLaunch' -Tag 'lib' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:skillRoot = Join-Path $root 'skill'
        New-Item -ItemType Directory -Path (Join-Path $script:skillRoot 'scripts\windows') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') -Value 'param()'
        $script:launch = New-ElevatedLaunch -OutputBase (Join-Path $root 'out') -StateBase (Join-Path $root 'state') `
            -SkillRoot $script:skillRoot
        $script:received = [System.Collections.Generic.List[string]]::new()
        $script:fakeLauncher = { param($ArgumentString) $script:received.Add($ArgumentString); 7 }
    }

    It 'hands the launcher the record''s exact argument string and returns its exit code' {
        $code = Start-ElevatedLaunch -Launch $script:launch -Launcher $script:fakeLauncher

        $code | Should -Be 7
        @($script:received) | Should -Be @($script:launch.ArgumentString)
    }

    It 'refuses a record whose argument string was changed' {
        $tampered = $script:launch.PSObject.Copy()
        $tampered.ArgumentString = $tampered.ArgumentString.Replace('exit 3', 'exit 0')

        { Start-ElevatedLaunch -Launch $tampered -Launcher $script:fakeLauncher } | Should -Throw '*Refused*'
        $script:received.Count | Should -Be 0
    }
}

Describe 'Elevated pass round trip' -Tag 'lib' {
    It 'imports what the elevated side wrote into the file New-ElevatedLaunch prepared' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $skillRoot = Join-Path $root 'skill'
        New-Item -ItemType Directory -Path (Join-Path $skillRoot 'scripts\windows') | Out-Null
        Set-Content -LiteralPath (Join-Path $skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') -Value 'param()'
        $launch = New-ElevatedLaunch -OutputBase (Join-Path $root 'out') -StateBase (Join-Path $root 'state') -SkillRoot $skillRoot
        $result = { param($Id, $Severity, $Summary) [pscustomobject]@{
                id = $Id; category = 'storage'; os = 'windows'; ran_at = (Get-Date).ToString('o'); severity = $Severity
                summary = $Summary; detail = @{}; commands = @(); needs_admin = $true; ran_successfully = $true
                duration_ms = 1; trend = $null; notes = $null; error = $null
            } }
        Start-Sleep -Milliseconds 20

        # -Elevated $true stands in for the admin token.
        Write-ElevatedResult -Path $launch.ResultPath -FileId $launch.ResultFileId -Elevated $true `
            -Results @(& $result 'disk-space' 'WARN' 'elevated reading') -Log @('check_ok id=disk-space')
        $import = Import-ElevatedResult -Path $launch.ResultPath -CheckResults @(& $result 'disk-space' 'UNKNOWN' 'standard reading')

        $import.Rejected | Should -BeNullOrEmpty
        @($import.ElevatedChecks) | Should -Be @('disk-space')
        $import.Results[0].summary | Should -BeExactly 'elevated reading'
        @($import.Log) | Should -Be @('check_ok id=disk-space')
    }
}
