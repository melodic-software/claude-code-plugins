#Requires -Version 7.4

<#
.SYNOPSIS
Detect presence of known OEM driver/firmware update CLIs. Inventory-only;
never invokes them.

.DESCRIPTION
Returns an array of { vendor, cli_name, path, rationale } records. Used by
Test-Drivers to surface "vendor has a richer tool available -- run it
manually" in the INFO section. Per SKILL.md "No update installation" rule,
this helper never runs the tools.

Known vendors: Dell, Intel, ASUS, HP, Lenovo, MSI.
Windows-specific.
#>

function Get-VendorUpdateCli {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $candidates = @(
        @{
            Vendor    = 'Dell'
            CliName   = 'dcu-cli.exe'
            Paths     = @(
                "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe"
                "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
            )
            Rationale = 'Dell Command Update -- run dcu-cli /scan for driver/BIOS updates.'
        }
        @{
            Vendor    = 'Intel'
            CliName   = 'DSATray.exe'
            Paths     = @(
                "${env:ProgramFiles(x86)}\Intel\Driver and Support Assistant\DSATray.exe"
                "$env:ProgramFiles\Intel\Driver and Support Assistant\DSATray.exe"
            )
            Rationale = 'Intel Driver & Support Assistant -- GUI tool; no CLI scan.'
        }
        @{
            Vendor    = 'HP'
            CliName   = 'HPImageAssistant.exe'
            Paths     = @(
                "$env:ProgramFiles\HPIA\HPImageAssistant.exe"
                "${env:ProgramFiles(x86)}\HPIA\HPImageAssistant.exe"
                "$env:ProgramData\HP\HPIA\HPImageAssistant.exe"
            )
            Rationale = 'HP Image Assistant -- run HPImageAssistant /Operation:Analyze.'
        }
        @{
            Vendor    = 'Lenovo'
            CliName   = 'TVSU_Launcher.exe'
            Paths     = @(
                "$env:ProgramFiles\Lenovo\System Update\tvsu.exe"
                "${env:ProgramFiles(x86)}\Lenovo\System Update\tvsu.exe"
            )
            Rationale = 'Lenovo System Update / Vantage -- check for driver + BIOS updates.'
        }
        @{
            Vendor    = 'MSI'
            CliName   = 'MSICenter.exe'
            Paths     = @(
                "$env:ProgramFiles\MSI\MSI Center\MSICenter.exe"
            )
            Rationale = 'MSI Center -- Support > Live Update.'
        }
    )

    $found = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($c in $candidates) {
        foreach ($p in $c.Paths) {
            if (Test-Path -LiteralPath $p) {
                $found.Add([pscustomobject]@{
                        vendor    = $c.Vendor
                        cli_name  = $c.CliName
                        path      = $p
                        rationale = $c.Rationale
                    })
                break
            }
        }
    }

    # ASUS special-case: MyASUS is a Store app, so it gets no filesystem
    # candidate above -- a naive scan of WindowsApps is too expensive. The
    # AppxPackage probe below is fast and is the only ASUS detection path.
    try {
        $myAsus = Get-AppxPackage -Name *MyASUS* -ErrorAction SilentlyContinue
        if ($myAsus) {
            $found.Add([pscustomobject]@{
                    vendor    = 'ASUS'
                    cli_name  = 'MyASUS'
                    path      = $myAsus.InstallLocation
                    rationale = 'MyASUS Store app installed -- check Customer Support > System Update.'
                })
        }
    } catch {
        Write-Verbose "Get-VendorUpdateCli: MyASUS probe skipped. $($_.Exception.Message)"
    }

    return $found.ToArray()
}
