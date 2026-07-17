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

PowerShell doesn't throw on native-command non-zero exit by default, so
we check Get-Command nvidia-smi FIRST and skip invocation entirely when
absent. This avoids silent "command not found" garbage on stdout.

Windows-specific (Win32_VideoController is WMI).
#>

function Get-GpuDriverInfo {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $out = [System.Collections.Generic.List[pscustomobject]]::new()

    # NVIDIA via nvidia-smi (only if installed).
    $nvCmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvCmd) {
        try {
            $raw = & nvidia-smi --query-gpu=name, driver_version `
                --format=csv, noheader 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                foreach ($line in ($raw -split "`r?`n")) {
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
            }
        } catch {
            Write-Verbose "Get-GpuDriverInfo: nvidia-smi failed. $($_.Exception.Message)"
        }
    }

    # spellchecker:ignore-next-line
    # Intel / AMD via Win32_VideoController (PnP).
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
