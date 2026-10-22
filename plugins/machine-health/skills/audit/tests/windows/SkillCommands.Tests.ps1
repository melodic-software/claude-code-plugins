#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Parses the PowerShell command templates in SKILL.md with hostile roots.

.DESCRIPTION
Claude Code substitutes ${CLAUDE_PLUGIN_ROOT}, ${CLAUDE_PLUGIN_DATA} and
${user_config.report_dir} into skill content as text, so a root reaches each
command as typed characters. Each template, run after the roots block, must
parse to the same commands whatever a root holds: PowerShell reads U+2018 to
U+201B as single quotes, and $( ) runs code outside a single-quoted string.
The fallback values come from SKILL.md, "Resolving output locations".
#>

BeforeAll {
    . "$PSScriptRoot\..\helpers\Initialize-CheckSuite.ps1"
    $skillText = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'SKILL.md') -Raw
    # A fence indented under a list item indents its lines by the same amount.
    $script:Blocks = @([regex]::Matches($skillText, '(?ms)^([ \t]*)```powershell\r?\n(.*?)^[ \t]*```') | ForEach-Object {
            $indent = $_.Groups[1].Value
            ($_.Groups[2].Value -split '\r?\n' | ForEach-Object {
                if ($indent -and $_.StartsWith($indent)) { $_.Substring($indent.Length) } else { $_ }
            }) -join "`n"
        })
    $script:Tokens = @('${CLAUDE_PLUGIN_ROOT}', '${CLAUDE_PLUGIN_DATA}', '${user_config.report_dir}')

    function Get-CommandList {
        param([string] $Text)
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
        $names = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object {
                    $name = $_.GetCommandName()
                    if ($name) { $name } elseif ($_.InvocationOperator -eq 'Dot') { '.' } else { '&' }
                } | Sort-Object)
        return [pscustomobject]@{ Errors = @($errors); Names = $names }
    }

    function Format-RootTemplate {
        param([string] $Text, [string] $Value)
        foreach ($token in $script:Tokens) { $Text = $Text.Replace($token, $Value) }
        return $Text
    }

    function Invoke-RootsBlock {
        param([string] $Text)
        $block = [scriptblock]::Create($Text + "`n" +
            '[pscustomobject]@{ Skill = $skillRoot; State = $stateRoot; Report = $reportRoot }')
        & $block 3>$null
    }
}

Describe 'SKILL.md command templates' -Tag 'skill' {
    It 'holds the roots block and four commands' {
        $script:Blocks.Count | Should -Be 5
        foreach ($token in $script:Tokens) { $script:Blocks[0] | Should -BeLike "*$token*" }
        # The PowerShell tool takes newlines only inside a here-string.
        @($script:Blocks[0].Trim() -split '\n').Count | Should -Be 5
        foreach ($command in $script:Blocks[1..4]) { @($command.Trim() -split '\n').Count | Should -Be 1 }
    }

    Context 'a root holding <Case>' -ForEach @(
        @{ Case = 'U+2019 around $( )'; Root = "C:\x$([char]0x2019) `$(New-Item canary) $([char]0x2019)" }
        @{ Case = 'U+2019 around a statement'; Root = "C:\x$([char]0x2019); New-Item canary; $([char]0x2019)" }
        @{ Case = 'an apostrophe'; Root = "C:\x'; New-Item canary; '" }
        @{ Case = 'U+201B around $( )'; Root = "C:\x$([char]0x201B) `$(New-Item canary) $([char]0x201B)" }
        @{ Case = 'a leading here-string close'; Root = "'@ `$(New-Item canary)" }
        @{ Case = 'a leading U+2019 here-string close'; Root = "$([char]0x2019)@; New-Item canary" }
    ) {
        It 'parses the <Name> command to only its own commands' -ForEach @(
            @{ Name = 'roots'; Index = 0; Expected = @('ForEach-Object', 'Join-Path', 'Write-Warning') }
            @{ Name = 'run'; Index = 1; Expected = @('&', 'Join-Path') }
            @{ Name = 'prepare'; Index = 2; Expected = @('.', 'Format-List', 'Get-Content', 'Join-Path', 'New-ElevatedLaunch') }
            @{ Name = 'launch'; Index = 3; Expected = @('.', 'Get-ElevatedLaunch', 'Join-Path', 'Start-ElevatedLaunch') }
            @{ Name = 'import'; Index = 4; Expected = @('&', '.', 'Get-ElevatedLaunch', 'Join-Path', 'Join-Path') }
        ) {
            # SKILL.md appends a command to the roots block's last line after '; '.
            $command = if ($Index -eq 0) { '' } else { '; ' + $script:Blocks[$Index].Trim().Replace('<ScriptSha256>', 'AB' * 32) }
            $text = (Format-RootTemplate $script:Blocks[0] $Root).TrimEnd() + $command

            $parsed = Get-CommandList $text

            $parsed.Errors.Count | Should -Be 0
            $rootNames = @('ForEach-Object', 'Join-Path', 'Write-Warning')
            $want = @($(if ($Index -eq 0) { $Expected } else { $rootNames + $Expected }) | Sort-Object)
            $parsed.Names | Should -Be $want
        }

        It 'binds each root to exactly the substituted text' {
            Push-Location -LiteralPath $TestDrive
            try {
                $roots = Invoke-RootsBlock (Format-RootTemplate $script:Blocks[0] $Root)
            } finally {
                Pop-Location
            }

            $roots.Skill | Should -BeExactly "$Root/skills/audit"
            $roots.State | Should -BeExactly $Root
            $roots.Report | Should -BeExactly $Root
            Test-Path -LiteralPath (Join-Path $TestDrive 'canary') | Should -BeFalse
        }
    }

    It 'defaults the report root and puts state under it when neither token was substituted' {
        $roots = Invoke-RootsBlock $script:Blocks[0]

        $roots.Report | Should -BeExactly (Join-Path $env:USERPROFILE 'Documents\MachineHealth')
        $roots.State | Should -BeExactly $roots.Report
    }

    It 'keeps a substituted data folder when only the report option is unset' {
        $text = $script:Blocks[0].Replace('${CLAUDE_PLUGIN_DATA}', 'D:\data\machine-health')

        $roots = Invoke-RootsBlock $text

        $roots.State | Should -BeExactly 'D:\data\machine-health'
        $roots.Report | Should -BeExactly (Join-Path $env:USERPROFILE 'Documents\MachineHealth')
    }
}
