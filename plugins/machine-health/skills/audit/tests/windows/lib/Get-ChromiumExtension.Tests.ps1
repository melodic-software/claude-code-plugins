#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.DESCRIPTION
The fixtures are synthetic shapes from a 2026-10-21 read of a Windows 11
host's Edge and Chrome profiles, with every value redacted: Edge keeps
location-less stub entries, and one extension's state can be split across
Preferences and Secure Preferences.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ChromiumExtension.ps1'

    # Under TestDrive so the provider cmdlets' -LiteralPath binds; nothing is written there.
    $script:Root = [System.IO.Path]::Combine($TestDrive, 'User Data')
    $script:InstallDir = [System.IO.Path]::Combine($TestDrive, 'Program Files', 'Browser', 'Application')

    # Mock bodies reach the fake files by closure.
    $script:Fake = @{ files = @{}; sizes = @{}; appPath = $null }
    $fake = $script:Fake
    Set-Item -Path function:Get-FakeFile -Value ({ param([string] $Path) $fake['files'][$Path] }.GetNewClosure())
    Set-Item -Path function:Get-FakeSize -Value ({ param([string] $Path) $fake['sizes'][$Path] }.GetNewClosure())
    Set-Item -Path function:Get-FakeAppPath -Value ({ $fake['appPath'] }.GetNewClosure())

    function Register-PrefFile {
        param([string] $Relative, $Object, [string] $Text)
        $path = [System.IO.Path]::Combine($script:Root, $Relative)
        $script:Fake['files'][$path] = if ($PSBoundParameters.ContainsKey('Text')) { $Text } else { $Object | ConvertTo-Json -Depth 10 }
    }

    function Register-Profile {
        param([string[]] $Names = @('Default'))
        $cache = @{}
        foreach ($n in $Names) { $cache[$n] = @{ name = "Display $n" } }
        Register-PrefFile 'Local State' @{ profile = @{ info_cache = $cache } }
    }
}

Describe 'Get-ChromiumExtension' -Tag 'lib' {
    BeforeEach {
        $script:Fake['files'].Clear()
        $script:Fake['sizes'].Clear()
        $script:Fake['appPath'] = [System.IO.Path]::Combine($script:InstallDir, 'browser.exe')
        Mock Get-Item {
            $path = @($LiteralPath)[0]
            $text = Get-FakeFile $path
            if ($null -eq $text) { throw [System.Management.Automation.ItemNotFoundException]::new("missing $path") }
            $size = Get-FakeSize $path
            [pscustomobject]@{ Length = $(if ($null -ne $size) { $size } else { $text.Length }) }
        }
        Mock Get-Content { Get-FakeFile @($LiteralPath)[0] }
        Mock Get-ItemProperty {
            $exe = Get-FakeAppPath
            if (@($LiteralPath)[0] -like 'HKLM:*' -and $exe) { return [pscustomobject]@{ '(default)' = $exe } }
            throw [System.Management.Automation.ItemNotFoundException]::new('no app path')
        }
    }

    It 'returns absent with no records when Local State does not exist' {
        $r = Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root
        $r.ReadState | Should -Be 'absent'
        @($r.Extensions).Count | Should -Be 0
    }

    It 'returns denied when Local State cannot be read' {
        Mock Get-Item { throw [System.UnauthorizedAccessException]::new('denied') }
        (Get-ChromiumExtension -Browser 'edge' -UserDataRoot $script:Root).ReadState | Should -Be 'denied'
    }

    It 'merges both preference files per id and drops location-less stubs, counting them' {
        Register-Profile
        Register-PrefFile 'Default\Preferences' @{ extensions = @{ settings = @{
                    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = @{ location = 1; from_webstore = $true; path = 'aaaa\1.2_0' }
                } } }
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = @{ manifest = @{ name = 'Alpha'; version = '1.2' }; disable_reasons = @() }
                    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb = @{ active_permissions = @{ api = @('tabs') } }
                    cccccccccccccccccccccccccccccccc = @{ active_permissions = @{ api = @() } }
                } } }

        $r = Get-ChromiumExtension -Browser 'edge' -UserDataRoot $script:Root
        $r.ReadState | Should -Be 'ok'
        $r.ProfileCount | Should -Be 1
        $r.StubsSkipped | Should -Be 2
        @($r.Extensions).Count | Should -Be 1
        $e = $r.Extensions[0]
        $e.ExtId | Should -Be 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $e.Name | Should -Be 'Alpha'
        $e.Version | Should -Be '1.2'
        $e.ProfileDir | Should -Be 'Default'
        $e.LocationKind | Should -Be 'store'
        $e.FromWebstore | Should -BeTrue
        $e.Enabled | Should -BeTrue
        $e.PathIsAbsolute | Should -BeFalse
    }

    It 'maps location <Value> to <Kind>' -ForEach @(
        @{ Value = 4; Kind = 'unpacked' }
        @{ Value = 8; Kind = 'command-line' }
        @{ Value = 9; Kind = 'policy' }
        @{ Value = 3; Kind = 'external' }
        @{ Value = 10; Kind = 'external' }
        @{ Value = 42; Kind = 'unknown' }
        @{ Value = 'seven'; Kind = 'unknown' }
    ) {
        Register-Profile
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    dddddddddddddddddddddddddddddddd = @{ location = $Value; manifest = @{ name = 'D' } }
                } } }
        $r = Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root
        $r.ReadState | Should -Be 'ok'
        $r.Extensions[0].LocationKind | Should -Be $Kind
    }

    It 'says whether a component path lies under the browser install folder' {
        Register-Profile
        $inside = [System.IO.Path]::Combine($script:InstallDir, '131.0', 'resources', 'pdf')
        $outside = [System.IO.Path]::Combine($TestDrive, 'Elsewhere', 'pdf')
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee = @{ location = 5; path = $inside }
                    ffffffffffffffffffffffffffffffff = @{ location = 5; path = $outside }
                } } }
        $byId = @{}
        (Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root).Extensions | ForEach-Object { $byId[$_.ExtId] = $_ }
        $byId['eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'].UnderBrowserInstall | Should -BeTrue
        $byId['ffffffffffffffffffffffffffffffff'].UnderBrowserInstall | Should -BeFalse
        $byId['ffffffffffffffffffffffffffffffff'].PathIsAbsolute | Should -BeTrue
    }

    It 'leaves UnderBrowserInstall unknown when the install folder cannot be read' {
        $script:Fake['appPath'] = $null
        Register-Profile
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee = @{ location = 5; path = [System.IO.Path]::Combine($script:InstallDir, 'x') }
                } } }
        (Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root).Extensions[0].UnderBrowserInstall | Should -BeNullOrEmpty
    }

    It 'reads disabled state from a reason list or a bitmask, and permissions from active_permissions' {
        Register-Profile
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee = @{ location = 1; disable_reasons = @(1)
                        active_permissions = @{ api = @('debugger', 'storage', @{ socket = @() }); explicit_host = @('<all_urls>'); scriptable_host = @('https://example.test/*') }
                    }
                    ffffffffffffffffffffffffffffffff = @{ location = 1; disable_reasons = 2 }
                    gggggggggggggggggggggggggggggggg = @{ location = 1; disable_reasons = 0 }
                    hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh = @{ location = 1; disable_reasons = 'garbled' }
                } } }
        $byId = @{}
        (Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root).Extensions | ForEach-Object { $byId[$_.ExtId] = $_ }
        $byId['eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'].Enabled | Should -BeFalse
        $byId['ffffffffffffffffffffffffffffffff'].Enabled | Should -BeFalse
        $byId['gggggggggggggggggggggggggggggggg'].Enabled | Should -BeTrue
        $byId['hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh'].Enabled | Should -BeNullOrEmpty
        $byId['eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'].ApiPermissions | Should -Be @('debugger', 'storage')
        $byId['eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'].HostPatterns | Should -Be @('<all_urls>', 'https://example.test/*')
    }

    It 'sets only the bad profile to error for <Case>, and keeps the other profile' -ForEach @(
        @{ Case = 'unparsable JSON'; Text = '{ not json' }
        @{ Case = 'a JSON root that is not an object'; Text = '[1, 2, 3]' }
    ) {
        Register-Profile -Names @('Default', 'Profile 2')
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh = @{ location = 1 }
                } } }
        Register-PrefFile 'Profile 2\Secure Preferences' -Text $Text
        $r = Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root
        $r.ReadState | Should -Be 'error'
        @($r.Extensions).Count | Should -Be 1
        ($r.Profiles | Where-Object ProfileDir -eq 'Default').ReadState | Should -Be 'ok'
        ($r.Profiles | Where-Object ProfileDir -eq 'Profile 2').ReadState | Should -Be 'error'
    }

    It 'refuses a profile file above the size cap without reading it' {
        Register-Profile
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{} } }
        $script:Fake['sizes'][[System.IO.Path]::Combine($script:Root, 'Default\Secure Preferences')] = $script:BrowserFileMaxBytes + 1
        $r = Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root
        $r.Profiles[0].ReadState | Should -Be 'error'
        Should -Invoke Get-Content -Times 0 -ParameterFilter { @($LiteralPath)[0] -like '*Secure Preferences' }
    }

    It 'sets a profile to error when its name is a path, not a folder name' {
        Register-Profile -Names @('..\..\elsewhere')
        $r = Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root
        $r.Profiles[0].ReadState | Should -Be 'error'
        $r.ReadState | Should -Be 'error'
    }

    It 'reports error when Local State has no profile cache' {
        Register-PrefFile 'Local State' @{ browser = @{} }
        (Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root).ReadState | Should -Be 'error'
    }
}
