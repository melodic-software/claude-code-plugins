#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.DESCRIPTION
The location-kind set and the size cap are this project's own decisions,
declared in New-ExtensionRecord.ps1 and described in check-catalog.md
section 23; the expected values below restate those decisions, not an
upstream source.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-ExtensionRecord.ps1'
    $script:Path = Join-Path $TestDrive 'prefs.json'
}

Describe 'New-ExtensionRecord' -Tag 'lib' {
    It 'carries every field it is given' {
        $r = New-ExtensionRecord -Browser 'edge' -ProfileDir 'Default' -ExtId 'abc' -Name 'N' -Version '1' `
            -LocationCode 4 -LocationKind 'unpacked' -FromWebstore $false -Enabled $true `
            -ApiPermissions @('tabs') -HostPatterns @('b', 'a', 'a') -PathIsAbsolute $true -UnderBrowserInstall $false
        $r.Browser | Should -Be 'edge'
        $r.LocationCode | Should -Be 4
        $r.LocationKind | Should -Be 'unpacked'
        $r.FromWebstore | Should -BeFalse
        $r.HostPatterns | Should -Be @('a', 'b')
        $r.PathIsAbsolute | Should -BeTrue
        $r.UnderBrowserInstall | Should -BeFalse
        $r.Signed | Should -BeNullOrEmpty
    }

    It 'stores an empty name or version as null' {
        $r = New-ExtensionRecord -Browser 'firefox' -ProfileDir 'p' -ExtId 'x' -Name '' -LocationKind 'store'
        $r.Name | Should -BeNullOrEmpty
        $r.Version | Should -BeNullOrEmpty
    }

    It 'refuses a location kind outside the declared set' {
        { New-ExtensionRecord -Browser 'chrome' -ProfileDir 'p' -ExtId 'x' -LocationKind 'sideloaded' } | Should -Throw
    }

    It 'refuses an empty extension id' {
        { New-ExtensionRecord -Browser 'chrome' -ProfileDir 'p' -ExtId '' -LocationKind 'store' } | Should -Throw
    }
}

Describe 'Read-BrowserJsonFile' -Tag 'lib' {
    BeforeEach {
        Mock Get-Item { [pscustomobject]@{ Length = 10 } }
    }

    It 'returns the parsed object' {
        Mock Get-Content { '{"a": 1}' }
        $r = Read-BrowserJsonFile -Path $script:Path
        $r.State | Should -Be 'ok'
        $r.Data['a'] | Should -Be 1
    }

    It 'reports error for <Case>' -ForEach @(
        @{ Case = 'unparsable text'; Text = '{ nope' }
        @{ Case = 'a root that is an array'; Text = '[1]' }
        @{ Case = 'a root that is a string'; Text = '"x"' }
    ) {
        Mock Get-Content { $Text }
        (Read-BrowserJsonFile -Path $script:Path).State | Should -Be 'error'
    }

    It 'reports error above the size cap without reading the file' {
        Mock Get-Item { [pscustomobject]@{ Length = $script:BrowserFileMaxBytes + 1 } }
        Mock Get-Content { '{}' }
        (Read-BrowserJsonFile -Path $script:Path).State | Should -Be 'error'
        Should -Invoke Get-Content -Times 0
    }

    It 'reports absent for a missing file and denied for a refused one' {
        Mock Get-Item { throw [System.Management.Automation.ItemNotFoundException]::new('missing') }
        (Read-BrowserJsonFile -Path $script:Path).State | Should -Be 'absent'
        Mock Get-Item { throw [System.UnauthorizedAccessException]::new('denied') }
        (Read-BrowserJsonFile -Path $script:Path).State | Should -Be 'denied'
    }
}
