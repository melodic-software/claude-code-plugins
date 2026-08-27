#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for skills/manage/scripts/firewall.ps1.

.DESCRIPTION
Pins the fix for the NetSecurity enum hazard (#3368). `Get-NetFirewallRule`'s
`Enabled` property is an enum whose members are True = 1 and False = 2, so BOTH
values are non-zero and BOTH coerce to boolean $true. The script used to test it
for truthiness, which meant `enable` reported "already enabled" against a
disabled rule and never re-enabled it, and `disable` called
`Disable-NetFirewallRule` against a rule that was already disabled.

.NOTES
Run from the repository root:

    Invoke-Pester -Path plugins/kindle-dedrm/skills/manage/tests -Output Detailed

The `enable` and `disable` branches sit behind an elevation gate that exits 2
before reaching the guard, and `Test-IsElevated` is defined inside the script,
so it shadows anything a test could inject. Those guards are therefore exercised
by lifting the REAL condition expressions out of the script's AST and evaluating
them against a rule object, rather than by asserting on a copy of the source
text. The `check` action needs no elevation and is driven end to end.
#>

# Mirrors Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled,
# which only exists once the Windows-only NetSecurity module is loaded. Declared
# locally so the suite runs anywhere; the first test cross-checks the two where
# the real type is available.
enum FakeNetSecurityEnabled {
    True = 1
    False = 2
}

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\firewall.ps1'

    # Returns the literal `if` condition guarding the enum test inside one switch
    # clause of firewall.ps1, as a runnable scriptblock plus its source text.
    function Get-EnabledGuard {
        param(
            [Parameter(Mandatory)] [string] $Path,
            [Parameter(Mandatory)] [string] $Action
        )
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$null, [ref]$null)
        $switchAst = $ast.Find(
            { param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] },
            $true)
        $clause = $switchAst.Clauses | Where-Object { $_.Item1.Extent.Text -eq "'$Action'" }
        if (-not $clause) { throw "No '$Action' clause in $Path." }
        $ifAst = $clause.Item2.Find({
                param($n)
                $n -is [System.Management.Automation.Language.IfStatementAst] -and
                $n.Clauses[0].Item1.Extent.Text -match '\$rule\.Enabled'
            }, $true)
        if (-not $ifAst) { throw "No `$rule.Enabled guard in the '$Action' clause of $Path." }
        $text = $ifAst.Clauses[0].Item1.Extent.Text
        return [pscustomobject]@{
            Text  = $text
            Guard = [scriptblock]::Create($text)
        }
    }
}

Describe 'firewall.ps1' {
    Context 'the Enabled enum this suite stands in for' {
        It 'matches the real NetSecurity enum: False is 2, non-zero, and renders "False"' {
            Import-Module NetSecurity -ErrorAction SilentlyContinue
            $real = 'Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled' -as [type]
            if (-not $real) {
                Set-ItResult -Skipped -Because 'the Windows-only NetSecurity module is unavailable'
                return
            }
            [int]$real::False | Should -Be ([int][FakeNetSecurityEnabled]::False)
            [int]$real::True | Should -Be ([int][FakeNetSecurityEnabled]::True)
            "$($real::False)" | Should -Be 'False'
            # The whole defect in one line: a DISABLED rule is boolean true.
            [bool]$real::False | Should -BeTrue
        }
    }

    Context 'enable guard' {
        It 'fires for a disabled rule so the rule is re-enabled' {
            $guard = Get-EnabledGuard -Path $script:ScriptPath -Action 'enable'
            $rule = [pscustomobject]@{ Enabled = [FakeNetSecurityEnabled]::False }
            [bool](& $guard.Guard) | Should -BeTrue -Because `
                "'$($guard.Text)' must treat a disabled rule as needing re-enabling"
        }

        It 'does not fire for an already-enabled rule' {
            $guard = Get-EnabledGuard -Path $script:ScriptPath -Action 'enable'
            $rule = [pscustomobject]@{ Enabled = [FakeNetSecurityEnabled]::True }
            [bool](& $guard.Guard) | Should -BeFalse
        }

        It 'is not a bare truthiness test' {
            $guard = Get-EnabledGuard -Path $script:ScriptPath -Action 'enable'
            $guard.Text | Should -BeLike '*True*'
        }
    }

    Context 'disable guard' {
        It 'does not fire for an already-disabled rule' {
            $guard = Get-EnabledGuard -Path $script:ScriptPath -Action 'disable'
            $rule = [pscustomobject]@{ Enabled = [FakeNetSecurityEnabled]::False }
            [bool](& $guard.Guard) | Should -BeFalse -Because `
                "'$($guard.Text)' must not call Disable-NetFirewallRule on a disabled rule"
        }

        It 'fires for an enabled rule' {
            $guard = Get-EnabledGuard -Path $script:ScriptPath -Action 'disable'
            $rule = [pscustomobject]@{ Enabled = [FakeNetSecurityEnabled]::True }
            [bool](& $guard.Guard) | Should -BeTrue
        }

        It 'is not a bare truthiness test' {
            $guard = Get-EnabledGuard -Path $script:ScriptPath -Action 'disable'
            $guard.Text | Should -BeLike '*True*'
        }
    }

    Context 'both guards tolerate a stringified Enabled' {
        It 'reads plain "False"/"True" strings the same way' {
            $enable = Get-EnabledGuard -Path $script:ScriptPath -Action 'enable'
            $disable = Get-EnabledGuard -Path $script:ScriptPath -Action 'disable'

            $rule = [pscustomobject]@{ Enabled = 'False' }
            [bool](& $enable.Guard) | Should -BeTrue
            [bool](& $disable.Guard) | Should -BeFalse

            $rule = [pscustomobject]@{ Enabled = 'True' }
            [bool](& $enable.Guard) | Should -BeFalse
            [bool](& $disable.Guard) | Should -BeTrue
        }
    }

    Context 'check action, end to end' {
        # Run in a child pwsh: firewall.ps1 calls `exit`, which escapes an
        # in-process `& $ScriptPath` and aborts the whole Pester run
        # (pester/Pester#2669). The child gets a Get-NetFirewallRule stub in its
        # global scope, which the script picks up because it defines no function
        # of that name itself.
        BeforeAll {
            function Invoke-FirewallCheck {
                param([Parameter(Mandatory)] [string] $EnabledMember)
                $child = @"
enum FakeNetSecurityEnabled { True = 1; False = 2 }
function Get-NetFirewallRule {
    param([string] `$DisplayName, `$ErrorAction)
    [pscustomobject]@{
        DisplayName = `$DisplayName
        Enabled     = [FakeNetSecurityEnabled]::$EnabledMember
        Action      = 'Block'
        Direction   = 'Outbound'
    }
}
& '$($script:ScriptPath)' -Action check
exit `$LASTEXITCODE
"@
                $out = pwsh -NoProfile -Command $child 2>&1 | Out-String
                return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
            }
        }

        It 'reports a disabled rule as Enabled=False rather than as enabled' {
            $r = Invoke-FirewallCheck -EnabledMember 'False'
            $r.Output | Should -Match 'present, Enabled=False'
            $r.ExitCode | Should -Be 0
        }

        It 'reports an enabled rule as Enabled=True' {
            $r = Invoke-FirewallCheck -EnabledMember 'True'
            $r.Output | Should -Match 'present, Enabled=True'
            $r.ExitCode | Should -Be 0
        }
    }
}
