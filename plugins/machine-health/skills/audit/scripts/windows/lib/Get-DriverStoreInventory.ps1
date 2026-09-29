#Requires -Version 7.4

<#
.SYNOPSIS
Parses `pnputil /enum-drivers` output into structured records.

.DESCRIPTION
# spellchecker:ignore-next-line
Win32_PnPSignedDriver.IsSigned is an unreliable signal on modern
Windows: cross-signed, attestation-signed, and test-signed drivers
return inconsistent values, and Secure Boot blocks most genuinely-
unsigned kernel drivers from loading at all. pnputil /enum-drivers
instead reports each driver's SignerName directly from the driver
store -- an empty SignerName means the driver has no recorded signer,
which is the real "unsigned" condition.

This wrapper runs pnputil through Invoke-NativeCommand, parses the localized
key: value output into PSCustomObjects, and returns them. A missing tool or a
non-zero exit returns an empty array, the same fallback as an invocation
failure. Tests mock this function to exercise the drivers check without
invoking the real pnputil.

English-locale field names:
  PublishedName, OriginalName, ProviderName, ClassName, DriverVersion,
  SignerName, Date, Version.

On non-English locales the field names differ -- callers should treat
SignerName absence as "unknown signer" rather than "unsigned", and
SignerName empty string as genuinely unsigned.
#>

. (Join-Path $PSScriptRoot 'Invoke-NativeCommand.ps1')

function Get-DriverStoreInventory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $invoked = Invoke-NativeCommand -Name 'pnputil' -ArgumentList @('/enum-drivers')
    if ($invoked.status -ne 'Ok') {
        Write-Verbose "Get-DriverStoreInventory: pnputil $($invoked.status) exit $($invoked.exit_code) $($invoked.error)"
        return @()
    }

    try {
        $raw = $invoked.output

        $records = $raw -split '(?m)^\s*$' | Where-Object { $_ -match '\S' }
        $result = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($rec in $records) {
            $entry = [ordered]@{}
            foreach ($line in $rec -split "`r?`n") {
                if ($line -match '^\s*([^:]+?)\s*:\s*(.*)$') {
                    $key = ($Matches[1] -replace '\s+', '')
                    $val = $Matches[2].Trim()
                    $entry[$key] = $val
                }
            }
            # Skip the pnputil header record (no PublishedName field)
            if ($entry.Contains('PublishedName')) {
                $result.Add([pscustomobject]$entry)
            }
        }
        return $result.ToArray()
    } catch {
        Write-Verbose "Get-DriverStoreInventory: pnputil output could not be parsed. $($_.Exception.Message)"
        return @()
    }
}
