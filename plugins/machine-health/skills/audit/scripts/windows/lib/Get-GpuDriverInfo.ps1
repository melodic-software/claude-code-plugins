#Requires -Version 7.4

<#
.SYNOPSIS
Detect installed GPUs (NVIDIA/Intel/AMD) and surface driver version info.

.DESCRIPTION
Returns an array of { vendor, model, driver_version, source } records.

NVIDIA: if `nvidia-smi` is on PATH, run it to fetch driver + GPU name.
# spellchecker:ignore-next-line
Intel/AMD: enumerate Win32_VideoController (PnP fallback; driver date
only). Never throws; missing vendor tooling just returns {} entries.

A missing tool or a non-zero exit leaves the NVIDIA record out and the
Win32_VideoController fallback still runs. Windows-specific
(Win32_VideoController is WMI).
#>

. (Join-Path $PSScriptRoot 'Invoke-NativeCommand.ps1')

function Get-GpuDriverInfo {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $out = [System.Collections.Generic.List[pscustomobject]]::new()

    # One string per argv entry. An unquoted comma in argument mode would split
    # the query into four entries and nvidia-smi would reject it (exit 2).
    $nv = Invoke-NativeCommand -Name 'nvidia-smi' -DiscardStdErr -ArgumentList @(
        '--query-gpu=name,driver_version',
        '--format=csv,noheader'
    )
    if ($nv.status -eq 'Ok' -and $nv.output) {
        foreach ($line in ($nv.output -split "`r?`n")) {
            $parts = $line -split ',' | ForEach-Object { $_.Trim() }
            if ($parts.Count -ge 2 -and $parts[0]) {
                $out.Add([pscustomobject]@{
                        vendor         = 'NVIDIA'
                        model          = $parts[0]
                        driver_version = $parts[1]
                        source         = 'nvidia-smi'
                    })
            }
        }
    } elseif ($nv.status -eq 'Failed') {
        Write-Verbose "Get-GpuDriverInfo: nvidia-smi failed. $($nv.error)"
    }

    try {
        $vcs = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        foreach ($vc in $vcs) {
            $vendor = switch -Regex ($vc.Name) {
                'Intel' { 'Intel' }
                'Advanced Micro Devices|AMD|Radeon' { 'AMD' }
                'NVIDIA|GeForce|Quadro|RTX|GTX' { $null }  # already covered above
                default { 'Other' }
            }
            if ($null -eq $vendor) { continue }

            $out.Add([pscustomobject]@{
                    vendor         = $vendor
                    model          = $vc.Name
                    driver_version = $vc.DriverVersion
                    driver_date    = if ($vc.DriverDate) { $vc.DriverDate.ToString('o') } else { $null }
                    source         = 'Win32_VideoController'
                })
        }
    } catch {
        Write-Verbose "Get-GpuDriverInfo: Win32_VideoController failed. $($_.Exception.Message)"
    }

    return $out.ToArray()
}
