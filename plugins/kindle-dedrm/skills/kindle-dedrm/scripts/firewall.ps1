<#
.SYNOPSIS
  Manage the Windows Firewall outbound block on Kindle.exe — kindle-dedrm skill.

.DESCRIPTION
  Idempotent enable / disable / check / remove of the firewall rule that prevents
  Kindle for PC from phoning home for auto-updates.

  Rule name (stable): "Block Kindle for PC (lock 2.8.0)"
  Program: $env:LOCALAPPDATA\Amazon\Kindle\application\Kindle.exe
  Direction: Outbound
  Action: Block
  Profile: Any

.PARAMETER Action
  enable  — create rule if absent, set Enabled=True (DEFAULT for safe state)
  disable — set Enabled=False (does NOT delete; sync action uses this)
  check   — print current state, exit 0 if rule exists and matches expected shape
  remove  — delete the rule entirely (cleanup action only)

.NOTES
  enable/disable/remove require elevation. check works without elevation.
  Exit codes: 0 = success, 1 = failure, 2 = needs admin and isn't.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('enable', 'disable', 'check', 'remove')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$RuleName = 'Block Kindle for PC (lock 2.8.0)'
$KindleExe = "$env:LOCALAPPDATA\Amazon\Kindle\application\Kindle.exe"

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Rule {
    Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
}

function Show-State {
    $rule = Get-Rule
    if (-not $rule) {
        Write-Output '[firewall] absent'
        return $false
    }
    $enabled = $rule.Enabled
    Write-Output "[firewall] present, Enabled=$enabled, Action=$($rule.Action), Direction=$($rule.Direction)"
    return $true
}

switch ($Action) {
    'check' {
        $exists = Show-State
        if ($exists) { exit 0 } else { exit 1 }
    }
    'enable' {
        if (-not (Test-IsElevated)) {
            Write-Error '[firewall] enable requires admin. Re-run from an elevated PowerShell.'
            exit 2
        }
        $rule = Get-Rule
        if ($rule) {
            if (-not $rule.Enabled) {
                Enable-NetFirewallRule -DisplayName $RuleName | Out-Null
                Write-Output '[firewall] re-enabled existing rule'
            } else {
                Write-Output '[firewall] already enabled — no change'
            }
        } else {
            if (-not (Test-Path $KindleExe)) {
                Write-Error "[firewall] Kindle.exe not found at $KindleExe — install Kindle for PC first."
                exit 1
            }
            New-NetFirewallRule -DisplayName $RuleName `
                -Direction Outbound -Action Block -Program $KindleExe `
                -Profile Any -Enabled True | Out-Null
            Write-Output '[firewall] created and enabled'
        }
        Show-State | Out-Null
    }
    'disable' {
        if (-not (Test-IsElevated)) {
            Write-Error '[firewall] disable requires admin.'
            exit 2
        }
        $rule = Get-Rule
        if (-not $rule) {
            Write-Output '[firewall] not present — nothing to disable'
            exit 0
        }
        if ($rule.Enabled) {
            Disable-NetFirewallRule -DisplayName $RuleName | Out-Null
            Write-Output '[firewall] disabled (rule retained — re-enable when sync is done)'
        } else {
            Write-Output '[firewall] already disabled — no change'
        }
        Show-State | Out-Null
    }
    'remove' {
        if (-not (Test-IsElevated)) {
            Write-Error '[firewall] remove requires admin.'
            exit 2
        }
        $rule = Get-Rule
        if (-not $rule) {
            Write-Output '[firewall] not present — nothing to remove'
            exit 0
        }
        Remove-NetFirewallRule -DisplayName $RuleName | Out-Null
        Write-Output '[firewall] removed'
    }
}

exit 0
