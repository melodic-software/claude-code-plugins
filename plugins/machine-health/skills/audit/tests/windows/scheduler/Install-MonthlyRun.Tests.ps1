#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for skills/setup/scripts/Install-MonthlyRun.ps1, which setup's schedule
step uses to write the monthly wrapper and its settings file, and its check
step uses to tell whether that copy is current.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1"
    $script:SetupRoot = Join-Path (Split-Path -Parent $script:SkillRoot) 'setup'
    . (Join-Path $script:SetupRoot 'scripts\Install-MonthlyRun.ps1')
    $script:Root = 'C:/Profile/A B/plugins/cache/machine-health/1.2.3'
}

Describe 'Get-MonthlyRunText' -Tag 'lib' {
    It 'writes the plugin root into the wrapper as a single-quoted literal and leaves no token' {
        $text = Get-MonthlyRunText -PluginRoot $script:Root
        $text | Should -Match ([regex]::Escape("`$pluginRoot = 'C:/Profile/A B/plugins/cache/machine-health/1.2.3'"))
        $text | Should -Not -Match '__PLUGIN_ROOT__'
    }

    It 'refuses a plugin root holding <Case>' -ForEach @(
        @{ Case = 'an apostrophe'; Char = "'" }
        @{ Case = 'U+2018'; Char = [string][char]0x2018 }
        @{ Case = 'U+2019'; Char = [string][char]0x2019 }
        @{ Case = 'U+201A'; Char = [string][char]0x201A }
        @{ Case = 'U+201B'; Char = [string][char]0x201B }
        @{ Case = 'a tab'; Char = "`t" }
        @{ Case = 'a line feed'; Char = "`n" }
        @{ Case = 'a carriage return'; Char = "`r" }
    ) {
        { Get-MonthlyRunText -PluginRoot "C:/Profile/a$($Char)b" } | Should -Throw '*plugin root*'
    }
}

Describe 'Assert-ScheduleRoot' -Tag 'lib' {
    It 'accepts roots with spaces and no quote or control character' {
        { Assert-ScheduleRoot -PluginRoot $script:Root -StateBase 'C:/Profile/A B/data/machine-health' } | Should -Not -Throw
    }

    It 'refuses a state folder holding <Case>' -ForEach @(
        @{ Case = 'U+2019'; Char = [string][char]0x2019 }
        @{ Case = 'an apostrophe'; Char = "'" }
    ) {
        { Assert-ScheduleRoot -PluginRoot $script:Root -StateBase "C:/Profile/a$($Char)b" } | Should -Throw '*state folder*'
    }

    It 'leaves no scheduler folder when Install-MonthlyRun refuses the state folder' {
        $base = Join-Path $TestDrive "bad$([char]0x2019)base"
        { Install-MonthlyRun -PluginRoot $script:Root -StateBase $base } | Should -Throw '*state folder*'
        Join-Path $base 'scheduler' | Should -Not -Exist
    }
}

Describe 'Install-MonthlyRun and Test-MonthlyRunCurrent' -Tag 'lib' {
    BeforeEach {
        $script:Base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Installed = Install-MonthlyRun -PluginRoot $script:Root -StateBase $script:Base
    }

    It 'writes the wrapper and the settings file into the scheduler folder under the state root' {
        $script:Installed.WrapperPath | Should -Be (Join-Path $script:Base 'scheduler\monthly-run.ps1')
        $script:Installed.SettingsPath | Should -Be (Join-Path $script:Base 'scheduler\scheduled-settings.json')
        $script:Installed.WrapperPath | Should -Exist
        $script:Installed.SettingsPath | Should -Exist
    }

    It 'reports a copy written for the same root as current' {
        $r = Test-MonthlyRunCurrent -PluginRoot $script:Root -StateBase $script:Base
        $r.WrapperCurrent | Should -BeTrue
        $r.SettingsCurrent | Should -BeTrue
    }

    It 'reports the wrapper stale once the plugin root moves' {
        $r = Test-MonthlyRunCurrent -PluginRoot 'C:/Profile/A B/plugins/cache/machine-health/1.2.4' -StateBase $script:Base
        $r.WrapperCurrent | Should -BeFalse
        $r.SettingsCurrent | Should -BeTrue
    }

    It 'reports the settings file stale when it was changed or removed' {
        Add-Content -LiteralPath $script:Installed.SettingsPath -Value ' '
        (Test-MonthlyRunCurrent -PluginRoot $script:Root -StateBase $script:Base).SettingsCurrent | Should -BeFalse
        Remove-Item -LiteralPath $script:Installed.SettingsPath
        (Test-MonthlyRunCurrent -PluginRoot $script:Root -StateBase $script:Base).SettingsCurrent | Should -BeFalse
    }
}

Describe 'scheduled-settings.json template' -Tag 'lib' {
    BeforeAll {
        $script:Settings = Get-Content -Raw -LiteralPath (Join-Path $script:SetupRoot 'templates\scheduled-settings.json') |
            ConvertFrom-Json -AsHashtable
    }

    It 'holds only permissions.deny, so every other user setting, enabledPlugins included, keeps its value' {
        @($script:Settings.Keys) | Should -Be @('permissions')
        @($script:Settings.permissions.Keys) | Should -Be @('deny')
    }

    It 'denies git, gh and the tools that write or act outside the TODO.md rule' {
        foreach ($rule in 'Bash(git *)', 'Bash(gh *)', 'PowerShell(git *)', 'PowerShell(gh *)', 'MultiEdit', 'NotebookEdit', 'Agent') {
            $script:Settings.permissions.deny | Should -Contain $rule
        }
    }

    It 'denies neither the tools the TODO.md write needs nor the audit commands' {
        foreach ($rule in $script:Settings.permissions.deny) {
            $rule | Should -Not -Match '^(Edit|Write|Read)(\(|$)'
            $rule | Should -Not -Match '^(Bash|PowerShell)(\(\*?\))?$'
            $rule | Should -Not -Match '^(Bash|PowerShell)\(pwsh'
        }
    }
}
