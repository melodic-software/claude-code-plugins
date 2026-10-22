#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Parses the PowerShell command templates in the audit and setup SKILL.md files
with hostile roots.

.DESCRIPTION
Claude Code substitutes ${CLAUDE_PLUGIN_ROOT}, ${CLAUDE_PLUGIN_DATA} and
${user_config.report_dir} into skill content as text, so a root reaches each
command as typed characters. Each template, run after its skill's roots block,
must parse to the same commands whatever a root holds: PowerShell reads U+2018
to U+201B as single quotes, and $( ) runs code outside a single-quoted string.
The fallback values come from the audit SKILL.md, "Resolving output locations".
#>

BeforeDiscovery {
    $script:HostileRoots = @(
        @{ Case = 'U+2019 around $( )'; Root = "C:\x$([char]0x2019) `$(New-Item canary) $([char]0x2019)" }
        @{ Case = 'U+2019 around a statement'; Root = "C:\x$([char]0x2019); New-Item canary; $([char]0x2019)" }
        @{ Case = 'an apostrophe'; Root = "C:\x'; New-Item canary; '" }
        @{ Case = 'U+2018 around $( )'; Root = "C:\x$([char]0x2018) `$(New-Item canary) $([char]0x2018)" }
        @{ Case = 'U+201A around a statement'; Root = "C:\x$([char]0x201A); New-Item canary; $([char]0x201A)" }
        @{ Case = 'U+201B around $( )'; Root = "C:\x$([char]0x201B) `$(New-Item canary) $([char]0x201B)" }
        @{ Case = 'a backtick before an apostrophe'; Root = "C:\x``'; New-Item canary; '" }
        @{ Case = 'a leading here-string close'; Root = "'@ `$(New-Item canary)" }
        @{ Case = 'a leading U+2019 here-string close'; Root = "$([char]0x2019)@; New-Item canary" }
    )
}

BeforeAll {
    . "$PSScriptRoot\..\helpers\Initialize-CheckSuite.ps1"

    # A fence indented under a list item indents its lines by the same amount.
    function Get-PowerShellBlock {
        param([string] $Path)
        $text = Get-Content -LiteralPath $Path -Raw
        @([regex]::Matches($text, '(?ms)^([ \t]*)```powershell\r?\n(.*?)^[ \t]*```') | ForEach-Object {
                $indent = $_.Groups[1].Value
                ($_.Groups[2].Value -split '\r?\n' | ForEach-Object {
                    if ($indent -and $_.StartsWith($indent)) { $_.Substring($indent.Length) } else { $_ }
                }) -join "`n"
            })
    }

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
        param([string] $Text, [string[]] $Token, [string] $Value)
        foreach ($t in $Token) { $Text = $Text.Replace($t, $Value) }
        return $Text
    }

    # The roots block with one command appended to its last line after '; ', as SKILL.md says.
    function Join-RootsCommand {
        param([string] $Roots, [string] $Command)
        if ($Command) { $Roots.TrimEnd() + '; ' + $Command.Trim() } else { $Roots.TrimEnd() }
    }

    function Invoke-RootsBlock {
        param([string] $Text, [string] $Result)
        $block = [scriptblock]::Create($Text + "`n" + $Result)
        & $block 3>$null
    }

    $script:AuditBlocks = Get-PowerShellBlock (Join-Path $script:SkillRoot 'SKILL.md')
    $script:AuditTokens = @('${CLAUDE_PLUGIN_ROOT}', '${CLAUDE_PLUGIN_DATA}', '${user_config.report_dir}')
    $script:SetupBlocks = Get-PowerShellBlock (Join-Path $script:SkillRoot '..\setup\SKILL.md')
    $script:SetupTokens = @('${CLAUDE_PLUGIN_ROOT}', '${CLAUDE_PLUGIN_DATA}', '<payload file>')
}

Describe 'audit SKILL.md command templates' -Tag 'skill' {
    It 'holds the roots block and five commands' {
        $script:AuditBlocks.Count | Should -Be 6
        foreach ($token in $script:AuditTokens) { $script:AuditBlocks[0] | Should -BeLike "*$token*" }
        # The PowerShell tool takes newlines only inside a here-string.
        @($script:AuditBlocks[0].Trim() -split '\n').Count | Should -Be 5
        foreach ($command in $script:AuditBlocks[1..5]) { @($command.Trim() -split '\n').Count | Should -Be 1 }
    }

    Context 'a root holding <Case>' -ForEach $script:HostileRoots {
        It 'parses the <Name> command to only its own commands' -ForEach @(
            @{ Name = 'roots'; Index = 0; Expected = @('ForEach-Object', 'Join-Path', 'Write-Warning') }
            @{ Name = 'run'; Index = 1; Expected = @('&', 'Join-Path') }
            @{ Name = 'short report'; Index = 2; Expected = @('&', 'Join-Path', 'Join-Path') }
            @{ Name = 'prepare'; Index = 3; Expected = @('.', 'Format-List', 'Get-Content', 'Join-Path', 'New-ElevatedLaunch') }
            @{ Name = 'launch'; Index = 4; Expected = @('.', 'Get-ElevatedLaunch', 'Join-Path', 'Start-ElevatedLaunch') }
            @{ Name = 'import'; Index = 5; Expected = @('&', '.', 'Get-ElevatedLaunch', 'Join-Path', 'Join-Path') }
        ) {
            $command = if ($Index -eq 0) { '' } else { $script:AuditBlocks[$Index].Replace('<ScriptSha256>', 'AB' * 32) }
            # Substituted across the command too, so a command that types a token itself fails.
            $text = Format-RootTemplate -Text (Join-RootsCommand $script:AuditBlocks[0] $command) -Token $script:AuditTokens -Value $Root

            $parsed = Get-CommandList $text

            $parsed.Errors.Count | Should -Be 0
            $rootNames = @('ForEach-Object', 'Join-Path', 'Write-Warning')
            $want = @($(if ($Index -eq 0) { $Expected } else { $rootNames + $Expected }) | Sort-Object)
            $parsed.Names | Should -Be $want
        }

        It 'binds each root to exactly the substituted text' {
            Push-Location -LiteralPath $TestDrive
            try {
                $roots = Invoke-RootsBlock (Format-RootTemplate -Text $script:AuditBlocks[0] -Token $script:AuditTokens -Value $Root) `
                    '[pscustomobject]@{ Skill = $skillRoot; State = $stateRoot; Report = $reportRoot }'
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
        $roots = Invoke-RootsBlock $script:AuditBlocks[0] '[pscustomobject]@{ State = $stateRoot; Report = $reportRoot }'

        $roots.Report | Should -BeExactly (Join-Path $env:USERPROFILE 'Documents\MachineHealth')
        $roots.State | Should -BeExactly $roots.Report
    }

    It 'keeps a substituted data folder when only the report option is unset' {
        $text = $script:AuditBlocks[0].Replace('${CLAUDE_PLUGIN_DATA}', 'D:\data\machine-health')

        $roots = Invoke-RootsBlock $text '[pscustomobject]@{ State = $stateRoot; Report = $reportRoot }'

        $roots.State | Should -BeExactly 'D:\data\machine-health'
        $roots.Report | Should -BeExactly (Join-Path $env:USERPROFILE 'Documents\MachineHealth')
    }
}

Describe 'setup SKILL.md command templates' -Tag 'skill' {
    It 'holds the roots block and three commands' {
        $script:SetupBlocks.Count | Should -Be 4
        foreach ($token in $script:SetupTokens) { $script:SetupBlocks[0] | Should -BeLike "*$token*" }
        @($script:SetupBlocks[0].Trim() -split '\n').Count | Should -Be 5
        foreach ($command in $script:SetupBlocks[1..3]) { @($command.Trim() -split '\n').Count | Should -Be 1 }
    }

    Context 'a root holding <Case>' -ForEach $script:HostileRoots {
        It 'parses the <Name> command to only its own commands' -ForEach @(
            @{ Name = 'roots'; Index = 0; Expected = @() }
            @{ Name = 'apply'; Index = 1; Expected = @('.', 'Join-Path', 'Set-ApprovalState') }
            @{ Name = 'picks resolve'; Index = 2
                Expected = @('.', 'ForEach-Object', 'Format-Table', 'Get-Content', 'Join-Path', 'Join-Path', 'Resolve-CheckupPick')
            }
            @{ Name = 'picks write'; Index = 3
                Expected = @('.', 'Get-Content', 'Join-Path', 'Write-CheckupPick')
            }
        ) {
            $command = if ($Index -eq 0) { '' } else {
                $script:SetupBlocks[$Index].Replace('<action> <arguments>', 'approve -RemediationId clear-temp-files').
                Replace('<confirmed mute numbers>', '1, 2').Replace('<confirmed approval numbers>', '3')
            }
            $text = Format-RootTemplate -Text (Join-RootsCommand $script:SetupBlocks[0] $command) -Token $script:SetupTokens -Value $Root

            $parsed = Get-CommandList $text

            $parsed.Errors.Count | Should -Be 0
            $parsed.Names | Should -Be (@(@('ForEach-Object') + $Expected) | Sort-Object)
        }

        It 'binds each root and the payload path to exactly the substituted text' {
            Push-Location -LiteralPath $TestDrive
            try {
                $roots = Invoke-RootsBlock (Format-RootTemplate -Text $script:SetupBlocks[0] -Token $script:SetupTokens -Value $Root) `
                    '[pscustomobject]@{ Plugin = $pluginRoot; State = $stateRoot; Payload = $payloadPath }'
            } finally {
                Pop-Location
            }

            $roots.Plugin | Should -BeExactly $Root
            $roots.State | Should -BeExactly $Root
            $roots.Payload | Should -BeExactly $Root
            Test-Path -LiteralPath (Join-Path $TestDrive 'canary') | Should -BeFalse
        }
    }

    It 'throws when the data folder token was not substituted' {
        $text = $script:SetupBlocks[0].Replace('${CLAUDE_PLUGIN_ROOT}', 'D:\plugins\machine-health')

        { Invoke-RootsBlock $text '$stateRoot' } | Should -Throw '*did not resolve*'
    }
}
