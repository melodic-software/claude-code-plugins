#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ChromiumExtension.ps1'

    # Under TestDrive so Get-Content's -LiteralPath binds; nothing is written there.
    $script:Root = [System.IO.Path]::Combine($TestDrive, 'User Data')

    function Register-PrefFile {
        <# Registers the JSON text Get-Content returns for one file under the fake user-data root. #>
        param([string] $Relative, $Object)
        $script:Files[([System.IO.Path]::Combine($script:Root, $Relative))] = ($Object | ConvertTo-Json -Depth 10)
    }
}

Describe 'Get-ChromiumExtension' -Tag 'lib' {
    BeforeEach {
        $script:Files = @{}
        Mock Get-Content {
            $path = @($LiteralPath)[0]
            if ($script:Files.ContainsKey($path)) { return $script:Files[$path] }
            throw [System.Management.Automation.ItemNotFoundException]::new("missing $LiteralPath")
        }
    }

    It 'returns absent with no records when Local State does not exist' {
        $r = Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root
        $r.ReadState | Should -Be 'absent'
        $r.ProfileCount | Should -Be 0
        @($r.Extensions).Count | Should -Be 0
    }

    It 'returns denied when Local State cannot be read' {
        Mock Get-Content { throw [System.UnauthorizedAccessException]::new('denied') }
        (Get-ChromiumExtension -Browser 'edge' -UserDataRoot $script:Root).ReadState | Should -Be 'denied'
    }

    It 'merges both preference files per id and drops location-less stubs, counting them' {
        Register-PrefFile 'Local State' @{ profile = @{ info_cache = @{ 'Default' = @{ name = 'Personal' } } } }
        # Full entry split across the two files: location in Preferences, manifest in Secure Preferences.
        Register-PrefFile 'Default\Preferences' @{ extensions = @{ settings = @{
                    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = @{ location = 1; from_webstore = $true }
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
        $e.ProfileName | Should -Be 'Personal'
        $e.LocationKind | Should -Be 'store'
        $e.FromWebstore | Should -BeTrue
        $e.Enabled | Should -BeTrue
    }

    It 'maps location codes to kinds, with unknown for a code it does not know' -TestCases @(
        @{ Code = 4; Kind = 'unpacked' }
        @{ Code = 8; Kind = 'command-line' }
        @{ Code = 9; Kind = 'policy' }
        @{ Code = 5; Kind = 'component' }
        @{ Code = 3; Kind = 'external' }
        @{ Code = 42; Kind = 'unknown' }
    ) {
        Register-PrefFile 'Local State' @{ profile = @{ info_cache = @{ 'Profile 1' = @{ name = 'Work' } } } }
        Register-PrefFile 'Profile 1\Secure Preferences' @{ extensions = @{ settings = @{
                    dddddddddddddddddddddddddddddddd = @{ location = $Code; manifest = @{ name = 'D' } }
                } } }
        $e = (Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root).Extensions[0]
        $e.LocationCode | Should -Be $Code
        $e.LocationKind | Should -Be $Kind
    }

    It 'reads disabled state from a reason list or a bitmask, and permissions from active_permissions' {
        Register-PrefFile 'Local State' @{ profile = @{ info_cache = @{ 'Default' = @{ name = 'P' } } } }
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee = @{ location = 1; disable_reasons = @(1)
                        active_permissions = @{ api = @('debugger', 'storage'); explicit_host = @('<all_urls>'); scriptable_host = @('https://example.test/*') }
                    }
                    ffffffffffffffffffffffffffffffff = @{ location = 1; disable_reasons = 2 }
                    gggggggggggggggggggggggggggggggg = @{ location = 1; disable_reasons = 0 }
                } } }
        $byId = @{}
        (Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root).Extensions | ForEach-Object { $byId[$_.ExtId] = $_ }
        $byId['eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'].Enabled | Should -BeFalse
        $byId['ffffffffffffffffffffffffffffffff'].Enabled | Should -BeFalse
        $byId['gggggggggggggggggggggggggggggggg'].Enabled | Should -BeTrue
        $byId['eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'].ApiPermissions | Should -Be @('debugger', 'storage')
        $byId['eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'].HostPatterns | Should -Be @('<all_urls>', 'https://example.test/*')
    }

    It 'keeps the records it read and reports error when one profile file is unparsable' {
        Register-PrefFile 'Local State' @{ profile = @{ info_cache = @{ 'Default' = @{ name = 'A' }; 'Profile 2' = @{ name = 'B' } } } }
        Register-PrefFile 'Default\Secure Preferences' @{ extensions = @{ settings = @{
                    hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh = @{ location = 1 }
                } } }
        $script:Files[(Join-Path $script:Root 'Profile 2\Secure Preferences')] = '{ not json'
        $r = Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root
        $r.ReadState | Should -Be 'error'
        @($r.Extensions).Count | Should -Be 1
    }

    It 'reports error when Local State has no profile cache' {
        Register-PrefFile 'Local State' @{ browser = @{} }
        (Get-ChromiumExtension -Browser 'chrome' -UserDataRoot $script:Root).ReadState | Should -Be 'error'
    }
}
