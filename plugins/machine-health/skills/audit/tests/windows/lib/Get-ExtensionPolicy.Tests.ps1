#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

<#
.DESCRIPTION
Store update URLs come from the Edge ExtensionInstallForcelist policy page on
Microsoft Learn (example value) and Chromium's policy_loader_common.cc
(kChromeWebstoreUpdateURL).
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ExtensionPolicy.ps1'

    $script:EdgeStore = 'https://edge.microsoft.com/extensionwebstorebase/v1/crx'
    $script:ChromeStore = 'https://clients2.google.com/service/update2/crx'
    $script:EdgeForce = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist'

    function Register-RegKey {
        param([string] $Path, [hashtable] $Values)
        $script:Keys[$Path] = $Values
    }

    function Get-Row {
        param($Result, [string] $Browser, [string] $Hive, [string] $Kind = 'forcelist')
        @($Result.Policies | Where-Object { $_.Browser -eq $Browser -and $_.Hive -eq $Hive -and $_.Kind -eq $Kind })[0]
    }
}

Describe 'Get-ExtensionPolicy' -Tag 'lib' {
    BeforeEach {
        $script:Keys = @{}
        $script:PartOfDomain = $false
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $script:PartOfDomain } }
        Mock Get-ItemProperty {
            $path = @($LiteralPath)[0]
            if (-not $script:Keys.ContainsKey($path)) {
                throw [System.Management.Automation.ItemNotFoundException]::new("missing $path")
            }
            $o = [pscustomobject]@{ PSPath = "Microsoft.PowerShell.Core\Registry::$path" }
            # Registry value names '1', '2' ...: Add-Member refuses numeric names, PSObject does not.
            foreach ($k in $script:Keys[$path].Keys) {
                $o.PSObject.Properties.Add([psnoteproperty]::new($k, $script:Keys[$path][$k]))
            }
            return $o
        }
    }

    It 'reads both browsers in both hives and labels each row, matched only where the key exists' {
        Register-RegKey $script:EdgeForce @{ '1' = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;$($script:EdgeStore)" }
        $r = Get-ExtensionPolicy
        $r.ReadState | Should -Be 'ok'
        @($r.Policies | Where-Object Kind -eq 'forcelist').Count | Should -Be 4
        (Get-Row -Result $r -Browser 'edge' -Hive 'hklm').Matched | Should -BeTrue
        (Get-Row -Result $r -Browser 'edge' -Hive 'hkcu').Matched | Should -BeFalse
        (Get-Row -Result $r -Browser 'chrome' -Hive 'hklm').Matched | Should -BeFalse
        (Get-Row -Result $r -Browser 'chrome' -Hive 'hkcu').Matched | Should -BeFalse
    }

    It 'reads only integer-named values and splits each on the first semicolon' {
        Register-RegKey $script:EdgeForce @{
            '1'     = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            '2'     = "cccccccccccccccccccccccccccccccc;$($script:EdgeStore);extra"
            'Other' = 'dddddddddddddddddddddddddddddddd'
            '10'    = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;'
        }
        $row = Get-Row -Result (Get-ExtensionPolicy) -Browser 'edge' -Hive 'hklm'
        $row.Entries | Should -Be 3
        @($row.Forcelist.ValueName) | Should -Be @('1', '2', '10')
        $row.Forcelist[0].ExtId | Should -Be 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        $row.Forcelist[0].UpdateUrl | Should -BeNullOrEmpty
        $row.Forcelist[1].ExtId | Should -Be 'cccccccccccccccccccccccccccccccc'
        $row.Forcelist[1].UpdateUrl | Should -Be "$($script:EdgeStore);extra"
        $row.Forcelist[2].UpdateUrl | Should -BeNullOrEmpty
    }

    It 'marks an off-store Edge entry listed-but-blocked off a domain, and a store or URL-less entry listed' {
        Register-RegKey $script:EdgeForce @{
            '1' = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;https://updates.example.test/crx'
            '2' = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;$($script:EdgeStore.ToUpperInvariant())"
            '3' = 'cccccccccccccccccccccccccccccccc'
        }
        $row = Get-Row -Result (Get-ExtensionPolicy) -Browser 'edge' -Hive 'hklm'
        @($row.Forcelist.InstallState) | Should -Be @('listed-but-blocked', 'listed', 'listed')
        $row.BlockedCount | Should -Be 1
    }

    It 'judges Chrome entries against the Chrome Web Store URL, not the Edge one' {
        Register-RegKey 'HKCU:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist' @{
            '1' = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;$($script:ChromeStore)"
            '2' = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;$($script:EdgeStore)"
        }
        $row = Get-Row -Result (Get-ExtensionPolicy) -Browser 'chrome' -Hive 'hkcu'
        @($row.Forcelist.InstallState) | Should -Be @('listed', 'listed-but-blocked')
    }

    It 'calls nothing blocked on a domain-joined machine' {
        $script:PartOfDomain = $true
        Register-RegKey $script:EdgeForce @{ '1' = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;https://updates.example.test/crx' }
        $r = Get-ExtensionPolicy
        $r.DomainJoined | Should -BeTrue
        (Get-Row -Result $r -Browser 'edge' -Hive 'hklm').Forcelist[0].InstallState | Should -Be 'listed'
    }

    It 'calls nothing blocked and records the failure when domain membership cannot be read' {
        Mock Get-CimInstance { throw [System.UnauthorizedAccessException]::new('denied') }
        Register-RegKey $script:EdgeForce @{ '1' = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;https://updates.example.test/crx' }
        $r = Get-ExtensionPolicy
        $r.DomainState | Should -Be 'denied'
        $r.DomainJoined | Should -BeNullOrEmpty
        (Get-Row -Result $r -Browser 'edge' -Hive 'hklm').Forcelist[0].InstallState | Should -Be 'listed'
    }

    It 'counts installing ExtensionSettings ids and the off-store ones among them' {
        Register-RegKey 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' @{ ExtensionSettings = (@{
                    '*'                                = @{ installation_mode = 'blocked' }
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' = @{ installation_mode = 'force_installed'; update_url = 'https://updates.example.test/crx' }
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' = @{ installation_mode = 'normal_installed'; update_url = $script:EdgeStore }
                    'cccccccccccccccccccccccccccccccc' = @{ installation_mode = 'allowed' }
                } | ConvertTo-Json -Depth 4) }
        $row = Get-Row -Result (Get-ExtensionPolicy) -Browser 'edge' -Hive 'hklm' -Kind 'extension-settings'
        $row.Matched | Should -BeTrue
        $row.Entries | Should -Be 2
        $row.BlockedCount | Should -Be 1
    }

    It 'reports denied when a policy key cannot be read' {
        Mock Get-ItemProperty { throw [System.Security.SecurityException]::new('denied') }
        (Get-ExtensionPolicy).ReadState | Should -Be 'denied'
    }

    It 'reports error for an unparsable ExtensionSettings value' {
        Register-RegKey 'HKCU:\SOFTWARE\Policies\Google\Chrome' @{ ExtensionSettings = '{ nope' }
        (Get-ExtensionPolicy).ReadState | Should -Be 'error'
    }
}
