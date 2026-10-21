#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-InstalledApp.ps1'

    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        function Get-AppxPackage {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSAvoidOverwritingBuiltInCmdlets', '',
                Justification = 'Defined only when the Appx module is absent so Pester can mock the call.')]
            param()
            throw 'Get-AppxPackage is not available'
        }
    }

    $script:Hklm = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'

    $script:Entries = @{
        'Editor'      = [pscustomobject]@{
            DisplayName     = 'Text Editor'
            InstallDate     = '20260115'
            InstallLocation = '"X:\Apps\Editor\"'
            DisplayIcon     = '"X:\Apps\Editor\editor.exe",0'
        }
        'IconOnly'    = [pscustomobject]@{ DisplayName = 'Viewer'; DisplayIcon = 'X:\Apps\Viewer\viewer.ico' }
        'Hidden'      = [pscustomobject]@{ DisplayName = 'Runtime'; SystemComponent = 1 }
        'KB1'         = [pscustomobject]@{ DisplayName = 'Editor update'; ParentKeyName = 'Editor' }
        'NoName'      = [pscustomobject]@{ InstallLocation = 'X:\Apps\Unnamed' }
        'BadDate'     = [pscustomobject]@{ DisplayName = 'Tool'; InstallDate = '15/01/2026' }
    }

    function Set-UninstallMock {
        Mock Get-ChildItem {
            foreach ($name in $script:Entries.Keys) {
                [pscustomobject]@{ PSChildName = $name; PSPath = "fixture::$name" }
            }
        } -ParameterFilter { $LiteralPath -eq $script:Hklm }
        Mock Get-ChildItem { throw [System.Management.Automation.ItemNotFoundException]::new('missing') } `
            -ParameterFilter { $LiteralPath -ne $script:Hklm }
        Mock Get-ItemProperty { $script:Entries[$LiteralPath.Substring('fixture::'.Length)] }
    }
}

Describe 'Get-InstalledApp' -Tag 'lib' {
    Context 'Uninstall entries' {
        BeforeEach {
            Set-UninstallMock
            Mock Get-AppxPackage { }
        }

        It 'keeps named, visible, top-level entries only' {
            $read = Get-InstalledApp
            $read.ReadState | Should -Be 'ok'
            @($read.Apps.Key | Sort-Object) | Should -Be @('BadDate', 'Editor', 'IconOnly')
        }

        It 'reads the install date, folder and executable, stripping quotes and the icon index' {
            $editor = (Get-InstalledApp).Apps | Where-Object Key -EQ 'Editor'
            $editor.Name | Should -Be 'Text Editor'
            $editor.Kind | Should -Be 'win32'
            $editor.InstallDate | Should -Be ([datetime]::new(2026, 1, 15))
            $editor.InstallDir | Should -Be 'X:\Apps\Editor'
            $editor.ExePath | Should -Be 'X:\Apps\Editor\editor.exe'
        }

        It 'leaves ExePath empty when DisplayIcon is not an executable, and InstallDate empty when unparsable' {
            $apps = (Get-InstalledApp).Apps
            ($apps | Where-Object Key -EQ 'IconOnly').ExePath | Should -BeNullOrEmpty
            ($apps | Where-Object Key -EQ 'BadDate').InstallDate | Should -BeNullOrEmpty
        }
    }

    Context 'packaged apps' {
        It 'lists user packages by family name and drops framework, resource and system packages' {
            Mock Get-ChildItem { throw [System.Management.Automation.ItemNotFoundException]::new('missing') }
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = 'Contoso.Notes'; PackageFamilyName = 'Contoso.Notes_abc123'; IsFramework = $false; IsResourcePackage = $false; SignatureKind = 'Store' }
                [pscustomobject]@{ Name = 'Contoso.Runtime'; PackageFamilyName = 'Contoso.Runtime_abc123'; IsFramework = $true; IsResourcePackage = $false; SignatureKind = 'Store' }
                [pscustomobject]@{ Name = 'Contoso.Lang'; PackageFamilyName = 'Contoso.Lang_abc123'; IsFramework = $false; IsResourcePackage = $true; SignatureKind = 'Store' }
                [pscustomobject]@{ Name = 'Windows.Shell'; PackageFamilyName = 'Windows.Shell_abc123'; IsFramework = $false; IsResourcePackage = $false; SignatureKind = 'System' }
            }

            $read = Get-InstalledApp

            $read.ReadState | Should -Be 'ok'
            @($read.Apps).Count | Should -Be 1
            $read.Apps[0].Key | Should -Be 'Contoso.Notes_abc123'
            $read.Apps[0].Kind | Should -Be 'store'
            $read.Apps[0].PackageFamilyName | Should -Be 'Contoso.Notes_abc123'
        }

        It 'reports error but keeps the Uninstall apps when the package read fails' {
            Set-UninstallMock
            Mock Get-AppxPackage { throw 'Appx unavailable' }

            $read = Get-InstalledApp

            $read.ReadState | Should -Be 'error'
            @($read.Apps).Count | Should -Be 3
        }
    }

    It 'reports denied when an Uninstall key is denied' {
        Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('denied') }
        Mock Get-AppxPackage { }
        (Get-InstalledApp).ReadState | Should -Be 'denied'
    }
}
