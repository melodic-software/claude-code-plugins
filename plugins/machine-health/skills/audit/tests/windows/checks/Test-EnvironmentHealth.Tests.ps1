#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-EnvironmentHealth.ps1.

.DESCRIPTION
The check reads persisted Environment registry keys via Get-Item. Tests
materialize fixtures/windows/Environment/*.json into temp directories and
mock Get-Item to return New-MockEnvironmentKey objects. $env:PATH is
redirected to the fixture's process_path so shadowing uses a known order
and the host PATH cannot leak into the result.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-EnvironmentHealth.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    $script:FixtureRoot = Join-Path $script:TestsRoot 'fixtures\windows\Environment'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force
    . (Join-Path $script:TestsRoot 'helpers\Invoke-CheckScript.ps1')

    function Expand-FixturePathValue {
        param($Spec, [hashtable] $TokenMap)
        $value = [string]$Spec.value
        foreach ($t in $TokenMap.Keys) {
            $value = $value.Replace("{$t}", $TokenMap[$t])
        }
        $padTo = 0
        if ($Spec.PSObject.Properties['pad_to'] -and $null -ne $Spec.pad_to) {
            $padTo = [int]$Spec.pad_to
        }
        if ($padTo -gt $value.Length) {
            $value = $value + ';' + ('x' * ($padTo - $value.Length - 1))
            if ($value.Length -gt $padTo) { $value = $value.Substring(0, $padTo) }
            elseif ($value.Length -lt $padTo) { $value += ('x' * ($padTo - $value.Length)) }
        }
        return $value
    }

    function Convert-FixtureScope {
        param($ScopeObject, [hashtable] $TokenMap)
        $entries = @{}
        if ($null -eq $ScopeObject) { return $entries }
        foreach ($prop in $ScopeObject.PSObject.Properties) {
            $spec = $prop.Value
            $kind = [string]$spec.kind
            $value = Expand-FixturePathValue -Spec $spec -TokenMap $TokenMap
            $entries[$prop.Name] = @{ Kind = $kind; Value = $value }
        }
        return $entries
    }

    function Import-EnvironmentFixture {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [string] $TempRoot
        )
        $doc = Get-Content -LiteralPath (Join-Path $script:FixtureRoot "$Name.json") -Raw | ConvertFrom-Json
        $tokenMap = @{}
        foreach ($prop in $doc.dirs.PSObject.Properties) {
            $token = $prop.Name
            $spec = $prop.Value
            $path = Join-Path $TempRoot $token
            $tokenMap[$token] = $path
            if ($spec.exists) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                foreach ($file in @($spec.files)) {
                    Set-Content -LiteralPath (Join-Path $path $file) -Value ''
                }
            }
        }

        $userEntries = Convert-FixtureScope -ScopeObject $doc.user -TokenMap $tokenMap
        $machineEntries = Convert-FixtureScope -ScopeObject $doc.machine -TokenMap $tokenMap

        $processParts = @()
        foreach ($part in @($doc.process_path)) {
            $expanded = [string]$part
            foreach ($t in $tokenMap.Keys) {
                $expanded = $expanded.Replace("{$t}", $tokenMap[$t])
            }
            $processParts += $expanded
        }

        return [pscustomobject]@{
            UserKey     = New-MockEnvironmentKey -Entries $userEntries
            MachineKey  = New-MockEnvironmentKey -Entries $machineEntries
            ProcessPath = ($processParts -join ';')
            TokenMap    = $tokenMap
        }
    }

    function Install-EnvironmentMocks {
        param($Fixture)
        $script:UserKey = $Fixture.UserKey
        $script:MachineKey = $Fixture.MachineKey
        # GetNewClosure: MockWith runs in the mocked command's scope, so
        # $script:UserKey would resolve against the check script (unset,
        # StrictMode UNKNOWN) rather than this test file.
        $userKey = $Fixture.UserKey
        $machineKey = $Fixture.MachineKey
        Mock Get-Item -ParameterFilter { $LiteralPath -eq 'HKCU:\Environment' } -MockWith (
            { $userKey }.GetNewClosure()
        )
        Mock Get-Item -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } -MockWith (
            { $machineKey }.GetNewClosure()
        )
    }

    function Invoke-EnvironmentHealthAsObject { Invoke-CheckScriptAsObject $script:ScriptPath }

    function Invoke-EnvironmentHealthRaw {
        return ((& $script:ScriptPath) | Where-Object { $_ }) -join "`n"
    }
}

Describe 'Test-EnvironmentHealth' -Tag 'check' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-env'
        $script:priorPath = $env:PATH
        $script:priorPathext = $env:PATHEXT
        $env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
    }

    AfterEach {
        $env:PATH = $script:priorPath
        $env:PATHEXT = $script:priorPathext
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    Context 'healthy fixture' {
        It 'emits a schema-valid OK CheckResult' {
            $fx = Import-EnvironmentFixture -Name 'healthy' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.id | Should -Be 'environment-health'
            $result.category | Should -Be 'config'
            $result.severity | Should -Be 'OK'
            $result.ran_successfully | Should -BeTrue
            $result.needs_admin | Should -BeFalse
            $result.detail.user_path_is_expand_sz | Should -BeTrue
            $result.detail.disable_autoupdater | Should -HaveCount 0
            $result.detail.missing_path_dirs | Should -HaveCount 0
            $result.detail.duplicate_path_entries | Should -HaveCount 0
            $result.detail.shadowed_executables | Should -HaveCount 0
            $result.detail.credential_named_vars | Should -HaveCount 0
            $result.notes | Should -Match 'Detect-only'
        }

        It 'supports -Human without throwing' {
            $fx = Import-EnvironmentFixture -Name 'healthy' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $out = & $script:ScriptPath -Human
            ($out | Out-String) | Should -Match '\[OK\] environment-health'
        }
    }

    Context 'DISABLE_AUTOUPDATER' {
        It 'warns when User-scope DISABLE_AUTOUPDATER is truthy' {
            $fx = Import-EnvironmentFixture -Name 'disable-autoupdater' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'WARN'
            $result.summary | Should -Match 'DISABLE_AUTOUPDATER'
            $result.detail.disable_autoupdater | Should -HaveCount 1
            $result.detail.disable_autoupdater[0].scope | Should -Be 'user'
            $result.detail.disable_autoupdater[0].disables_updates | Should -BeTrue
        }
    }

    Context 'PATH missing and duplicate entries' {
        It 'reports INFO for a missing dir and a duplicate User Path entry' {
            $fx = Import-EnvironmentFixture -Name 'duplicate-and-missing-path' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'INFO'
            $result.detail.missing_path_dirs | Should -HaveCount 1
            $result.detail.missing_path_dirs[0].scope | Should -Be 'user'
            $result.detail.duplicate_path_entries | Should -HaveCount 1
            $result.detail.duplicate_path_entries[0].count | Should -Be 2
        }
    }

    Context 'shadowed executables' {
        It 'reports INFO when User wins over Machine for the same name' {
            $fx = Import-EnvironmentFixture -Name 'shadowed-exe' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'INFO'
            $result.detail.shadowed_executables | Should -HaveCount 1
            $result.detail.shadowed_executables[0].name | Should -Be 'git.exe'
            $result.detail.shadowed_executables[0].winner_scope | Should -Be 'user'
            $result.detail.shadowed_executables[0].warn | Should -BeFalse
        }

        It 'warns when the winner is Machine while a User copy also exists' {
            $fx = Import-EnvironmentFixture -Name 'shadow-machine-wins' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'WARN'
            $result.detail.shadowed_executables | Should -HaveCount 1
            $result.detail.shadowed_executables[0].winner_scope | Should -Be 'machine'
            $result.detail.shadowed_executables[0].warn | Should -BeTrue
        }
    }

    Context 'User Path value kind and length' {
        It 'warns when HKCU Path is REG_SZ' {
            $fx = Import-EnvironmentFixture -Name 'path-reg-sz' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'WARN'
            $result.detail.user_path_kind | Should -Be 'String'
            $result.detail.user_path_is_expand_sz | Should -BeFalse
            $result.summary | Should -Match 'REG_SZ'
        }

        It 'warns when User Path length is at least 1800' {
            $fx = Import-EnvironmentFixture -Name 'path-length-warn' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'WARN'
            $result.detail.user_path_length | Should -Be 1800
        }

        It 'is CRIT when User Path length reaches 2047' {
            $fx = Import-EnvironmentFixture -Name 'path-length-crit' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'CRIT'
            $result.detail.user_path_length | Should -Be 2047
        }
    }

    Context 'credential-named variables' {
        It 'reports names and scopes and never reads or emits values' {
            $fx = Import-EnvironmentFixture -Name 'credential-names' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx

            $raw = Invoke-EnvironmentHealthRaw
            $raw | Should -Not -Match 'super-secret-gh-token-2866-must-never-appear'
            $raw | Should -Not -Match 'sk-planted-api-key-value-do-not-log'
            $raw | Should -Not -Match 'planted-secret-value-do-not-log'
            $raw | Should -Not -Match 'planted-password-value-do-not-log'

            $result = $raw | ConvertFrom-Json
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'WARN'
            $names = @($result.detail.credential_named_vars | ForEach-Object { $_.name }) | Sort-Object
            $names | Should -Be @('ACME_SECRET', 'DB_PASSWORD', 'GITHUB_TOKEN', 'MY_API_KEY')
            foreach ($row in $result.detail.credential_named_vars) {
                $row.PSObject.Properties.Name | Should -Not -Contain 'value'
                $row.scope | Should -Be 'user'
            }

            $fx.UserKey.GetValueCalls | Should -Not -Contain 'GITHUB_TOKEN'
            $fx.UserKey.GetValueCalls | Should -Not -Contain 'MY_API_KEY'
            $fx.UserKey.GetValueCalls | Should -Not -Contain 'ACME_SECRET'
            $fx.UserKey.GetValueCalls | Should -Not -Contain 'DB_PASSWORD'
            $fx.UserKey.GetValueCalls | Should -Contain 'Path'

            $human = (& $script:ScriptPath -Human | Out-String)
            $human | Should -Not -Match 'super-secret-gh-token-2866-must-never-appear'
        }
    }

    Context 'degraded machine scope' {
        It 'continues with User-scope findings when HKLM Environment is unreadable' {
            $fx = Import-EnvironmentFixture -Name 'disable-autoupdater' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            $script:UserKey = $fx.UserKey
            $userKey = $fx.UserKey
            Mock Get-Item -ParameterFilter { $LiteralPath -eq 'HKCU:\Environment' } -MockWith (
                { $userKey }.GetNewClosure()
            )
            Mock Get-Item -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } -MockWith {
                throw 'Access is denied.'
            }

            $result = Invoke-EnvironmentHealthAsObject
            $result.ran_successfully | Should -BeTrue
            $result.detail.machine_scope_readable | Should -BeFalse
            $result.detail.disable_autoupdater | Should -HaveCount 1
            $result.notes | Should -Match 'Machine Environment unreadable'
        }
    }

    Context 'must never write' {
        It 'does not call registry or environment mutators' {
            $fx = Import-EnvironmentFixture -Name 'healthy' -TempRoot $script:tmpDir
            $env:PATH = $fx.ProcessPath
            Install-EnvironmentMocks $fx
            Mock Set-ItemProperty { throw 'mutation forbidden: Set-ItemProperty' }
            Mock Set-Item { throw 'mutation forbidden: Set-Item' }
            Mock Clear-ItemProperty { throw 'mutation forbidden: Clear-ItemProperty' }
            Mock Remove-ItemProperty { throw 'mutation forbidden: Remove-ItemProperty' }

            $result = Invoke-EnvironmentHealthAsObject
            $result.ran_successfully | Should -BeTrue
            $result.severity | Should -Be 'OK'
        }
    }

    Context 'registry read failure' {
        It 'returns UNKNOWN when HKCU Environment cannot be read' {
            Mock Get-Item -ParameterFilter { $LiteralPath -eq 'HKCU:\Environment' } -MockWith {
                throw 'HKCU Environment missing'
            }
            Mock Get-Item -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } -MockWith {
                New-MockEnvironmentKey -Entries @{}
            }

            $result = Invoke-EnvironmentHealthAsObject
            $result.severity | Should -Be 'UNKNOWN'
            $result.ran_successfully | Should -BeFalse
            $result.error | Should -Match 'HKCU Environment missing'
        }
    }
}
