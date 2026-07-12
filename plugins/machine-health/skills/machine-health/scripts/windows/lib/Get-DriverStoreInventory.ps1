#Requires -Version 7.4

<#
.SYNOPSIS
Parses `pnputil /enum-drivers` output into structured records.

.DESCRIPTION
Win32_PnPSignedDriver.IsSigned is an unreliable signal on modern
Windows: cross-signed, attestation-signed, and test-signed drivers
return inconsistent values, and Secure Boot blocks most genuinely-
unsigned kernel drivers from loading at all. pnputil /enum-drivers
instead reports each driver's SignerName directly from the driver
store -- an empty SignerName means the driver has no recorded signer,
which is the real "unsigned" condition.

This wrapper runs pnputil, parses the localized key: value output into
PSCustomObjects, and returns them. Tests mock this function to
exercise the drivers check without invoking the real pnputil.

English-locale field names:
  PublishedName, OriginalName, ProviderName, ClassName, DriverVersion,
  SignerName, Date, Version.

On non-English locales the field names differ -- callers should treat
SignerName absence as "unknown signer" rather than "unsigned", and
SignerName empty string as genuinely unsigned.
#>

function Get-DriverStoreInventory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    try {
        $raw = & pnputil /enum-drivers 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Verbose "Get-DriverStoreInventory: pnputil exit $LASTEXITCODE"
            return @()
        }

        $records = $raw -split '(?m)^\s*$' | Where-Object { $_ -match '\S' }
        $result = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($rec in $records) {
            $entry = [ordered]@{}
            foreach ($line in $rec -split "`r?`n") {
                if ($line -match '^\s*([^:]+?)\s*:\s*(.*)$') {
                    $key = ($matches[1] -replace '\s+', '')
                    $val = $matches[2].Trim()
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
        Write-Verbose "Get-DriverStoreInventory: pnputil invocation failed. $($_.Exception.Message)"
        return @()
    }
}
