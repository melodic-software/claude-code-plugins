#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-FirefoxExtension.ps1'

    # Under TestDrive so Get-Content's -LiteralPath binds; nothing is written there.
    $script:Root = Join-Path $TestDrive 'Firefox'

    function Register-FxFile {
        param([string] $Relative, [string] $Text)
        $script:Files[(Join-Path $script:Root $Relative)] = $Text
    }

    function Get-TestAddon {
        param([string] $Id, [string] $Type = 'extension', [string] $Location = 'app-profile',
            $SignedState = 2, [bool] $Active = $true, [bool] $Foreign = $false, [string[]] $Origins = @())
        @{ id = $Id; type = $Type; version = '3.1'; active = $Active; location = $Location
            signedState = $SignedState; foreignInstall = $Foreign; defaultLocale = @{ name = "Name $Id" }
            userPermissions = @{ permissions = @('tabs'); origins = $Origins }
        }
    }
}

Describe 'Get-FirefoxExtension' -Tag 'lib' {
    BeforeEach {
        $script:Files = @{}
        Mock Get-Content {
            $path = @($LiteralPath)[0]
            if (-not $script:Files.ContainsKey($path)) {
                throw [System.Management.Automation.ItemNotFoundException]::new("missing $path")
            }
            $text = $script:Files[$path]
            if ($PSBoundParameters.ContainsKey('Raw')) { return $text }
            return $text -split "`n"
        }
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
            ) -join "`n")
        Register-FxFile 'Profiles\ab12.default-release\extensions.json' (@{ addons = @(
                    (Get-TestAddon -Id 'one@example.test' -Origins @('<all_urls>'))
                    (Get-TestAddon -Id 'theme@example.test' -Type 'theme')
                ) } | ConvertTo-Json -Depth 6)
        $script:Files[(Join-Path $abs 'extensions.json')] = (@{ addons = @(
                    (Get-TestAddon -Id 'two@example.test' -Location 'app-system-share' -SignedState 0 -Foreign $true -Active $false)
                ) } | ConvertTo-Json -Depth 6)

        $r = Get-FirefoxExtension -FirefoxRoot $script:Root
        $r.ReadState | Should -Be 'ok'
        $r.ProfileCount | Should -Be 2
        @($r.Extensions).Count | Should -Be 2

        $one = $r.Extensions | Where-Object ExtId -eq 'one@example.test'
        $one.ProfileDir | Should -Be 'ab12.default-release'
        $one.ProfileName | Should -Be 'default-release'
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

    It 'reports error for an unparsable extensions.json and unknown for an unmapped location' {
        Register-FxFile 'profiles.ini' "[Profile0]`nName=a`nIsRelative=1`nPath=Profiles/a`n[Profile1]`nName=b`nIsRelative=1`nPath=Profiles/b"
        Register-FxFile 'Profiles\a\extensions.json' '{ broken'
        Register-FxFile 'Profiles\b\extensions.json' (@{ addons = @((Get-TestAddon -Id 'x@example.test' -Location 'somewhere-new')) } | ConvertTo-Json -Depth 6)
        $r = Get-FirefoxExtension -FirefoxRoot $script:Root
        $r.ReadState | Should -Be 'error'
        $r.Extensions[0].LocationKind | Should -Be 'unknown'
    }

    It 'returns denied when profiles.ini cannot be read' {
        Mock Get-Content { throw [System.UnauthorizedAccessException]::new('denied') }
        (Get-FirefoxExtension -FirefoxRoot $script:Root).ReadState | Should -Be 'denied'
    }
}
