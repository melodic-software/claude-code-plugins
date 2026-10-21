#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.DESCRIPTION
signedState values come from Mozilla's AddonManager.sys.mjs SIGNEDSTATE_*
constants (0 missing, 2 signed), and location names from XPIProvider.sys.mjs
KEY_APP_* constants, both pinned in check-catalog.md section 23. Which kind
each location maps to is our judgment, recorded there. profiles.ini and
extensions.json are synthetic shapes with made-up ids.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-FirefoxExtension.ps1'

    # Under TestDrive so the provider cmdlets' -LiteralPath binds; nothing is written there.
    $script:Root = Join-Path $TestDrive 'Firefox'

    $script:Fake = @{}
    $fake = $script:Fake
    Set-Item -Path function:Get-FakeFile -Value ({ param([string] $Path) $fake[$Path] }.GetNewClosure())

    function Register-FxFile {
        param([string] $Relative, [string] $Text)
        $script:Fake[(Join-Path $script:Root $Relative)] = $Text
    }

    function Get-TestAddon {
        param([string] $Id, [string] $Type = 'extension', [string] $Location = 'app-profile',
            $SignedState = 2, $Active = $true, [bool] $Foreign = $false, [string[]] $Origins = @())
        @{ id = $Id; type = $Type; version = '3.1'; active = $Active; location = $Location
            signedState = $SignedState; foreignInstall = $Foreign; defaultLocale = @{ name = "Name $Id" }
            userPermissions = @{ permissions = @('tabs'); origins = $Origins }
        }
    }
}

Describe 'Get-FirefoxExtension' -Tag 'lib' {
    BeforeEach {
        $script:Fake.Clear()
        Mock Get-Item {
            $path = @($LiteralPath)[0]
            $text = Get-FakeFile $path
            if ($null -eq $text) { throw [System.Management.Automation.ItemNotFoundException]::new("missing $path") }
            [pscustomobject]@{ Length = $text.Length }
        }
        Mock Get-Content { Get-FakeFile @($LiteralPath)[0] }
    }

    It 'returns absent when Firefox has no profiles.ini' {
        $r = Get-FirefoxExtension -FirefoxRoot $script:Root
        $r.ReadState | Should -Be 'absent'
        $r.Browser | Should -Be 'firefox'
        @($r.Extensions).Count | Should -Be 0
    }

    It 'reads relative and absolute profiles and keeps only extensions' {
        $abs = Join-Path $TestDrive 'elsewhere\custom.profile'
        Register-FxFile 'profiles.ini' (@(
                '[General]', 'StartWithLastProfile=1',
                '[Profile0]', 'Name=default-release', 'IsRelative=1', 'Path=Profiles/ab12.default-release',
                '[Profile1]', 'Name=work', 'IsRelative=0', "Path=$abs",
                '[Install4F96D1932A9F858E]', 'Default=Profiles/ab12.default-release'
            ) -join "`r`n")
        Register-FxFile 'Profiles\ab12.default-release\extensions.json' (@{ addons = @(
                    (Get-TestAddon -Id 'one@example.test' -Origins @('<all_urls>'))
                    (Get-TestAddon -Id 'theme@example.test' -Type 'theme')
                ) } | ConvertTo-Json -Depth 6)
        $script:Fake[(Join-Path $abs 'extensions.json')] = (@{ addons = @(
                    (Get-TestAddon -Id 'two@example.test' -Location 'app-system-share' -SignedState 0 -Foreign $true -Active $false)
                ) } | ConvertTo-Json -Depth 6)

        $r = Get-FirefoxExtension -FirefoxRoot $script:Root
        $r.ReadState | Should -Be 'ok'
        $r.ProfileCount | Should -Be 2
        @($r.Extensions).Count | Should -Be 2

        $one = $r.Extensions | Where-Object ExtId -eq 'one@example.test'
        $one.ProfileDir | Should -Be 'ab12.default-release'
        $one.Name | Should -Be 'Name one@example.test'
        $one.LocationKind | Should -Be 'store'
        $one.Signed | Should -BeTrue
        $one.ForeignInstall | Should -BeFalse
        $one.Enabled | Should -BeTrue
        $one.HostPatterns | Should -Be @('<all_urls>')
        $one.LocationCode | Should -BeNullOrEmpty

        $two = $r.Extensions | Where-Object ExtId -eq 'two@example.test'
        $two.ProfileDir | Should -Be 'custom.profile'
        $two.LocationKind | Should -Be 'external'
        $two.Signed | Should -BeFalse
        $two.ForeignInstall | Should -BeTrue
        $two.Enabled | Should -BeFalse
    }

    It 'treats a profile with no extensions.json as holding nothing, not as a failed read' {
        Register-FxFile 'profiles.ini' "[Profile0]`nName=fresh`nIsRelative=1`nPath=Profiles/new.fresh"
        $r = Get-FirefoxExtension -FirefoxRoot $script:Root
        $r.ReadState | Should -Be 'ok'
        $r.ProfileCount | Should -Be 1
        @($r.Extensions).Count | Should -Be 0
    }

    It 'sets only the bad profile to error, and maps an unknown location to unknown in the good one' {
        Register-FxFile 'profiles.ini' "[Profile0]`nName=a`nIsRelative=1`nPath=Profiles/a`n[Profile1]`nName=b`nIsRelative=1`nPath=Profiles/b"
        Register-FxFile 'Profiles\a\extensions.json' '"just a string"'
        Register-FxFile 'Profiles\b\extensions.json' (@{ addons = @((Get-TestAddon -Id 'x@example.test' -Location 'somewhere-new')) } | ConvertTo-Json -Depth 6)
        $r = Get-FirefoxExtension -FirefoxRoot $script:Root
        $r.ReadState | Should -Be 'error'
        ($r.Profiles | Where-Object ProfileDir -eq 'a').ReadState | Should -Be 'error'
        ($r.Profiles | Where-Object ProfileDir -eq 'b').ReadState | Should -Be 'ok'
        $r.Extensions[0].LocationKind | Should -Be 'unknown'
    }

    It 'reads a malformed signedState as unsigned and a malformed active flag as unknown' {
        Register-FxFile 'profiles.ini' "[Profile0]`nIsRelative=1`nPath=Profiles/a"
        Register-FxFile 'Profiles\a\extensions.json' (@{ addons = @((Get-TestAddon -Id 'x@example.test' -SignedState 'signed' -Active 'yes')) } | ConvertTo-Json -Depth 6)
        $e = (Get-FirefoxExtension -FirefoxRoot $script:Root).Extensions[0]
        $e.Signed | Should -BeFalse
        $e.Enabled | Should -BeNullOrEmpty
    }

    It 'returns denied when profiles.ini cannot be read' {
        Mock Get-Item { throw [System.UnauthorizedAccessException]::new('denied') }
        (Get-FirefoxExtension -FirefoxRoot $script:Root).ReadState | Should -Be 'denied'
    }
}
