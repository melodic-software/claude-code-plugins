#Requires -Version 7.4

<#
.SYNOPSIS
Apply correlation rules to check results: pair related findings, upgrade
severity where warranted, cross-link via notes. Cross-OS framework.

.DESCRIPTION
Rules defined in-code (here), documented in references/shared/correlation-rules.md.
Only upgrades severity; never downgrades. Nothing downgrades -- trend analysis
upgrades too, so a severity this run raised stays raised for the run.

Always additive to notes; never truncates existing notes.
#>

function Get-CorrelationRule {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    return @(
        [pscustomobject]@{
            id = 'wu-reboot-retry-loop'
            Description = 'Windows Update reboot pending + WUClient/20 install failures'
            Apply = {
                param($Checks)
                $wu = $Checks | Where-Object id -EQ 'windows-update' | Select-Object -First 1
                $ev = $Checks | Where-Object id -EQ 'event-log-errors' | Select-Object -First 1
                if (-not $wu -or -not $ev) { return $null }
                if (-not $wu.detail -or -not $wu.detail.PSObject.Properties['reboot_pending']) { return $null }
                if (-not $wu.detail.reboot_pending) { return $null }
                if (-not $ev.detail -or -not $ev.detail.PSObject.Properties['top_sources']) { return $null }

                $wuClientHits = 0
                foreach ($src in @($ev.detail.top_sources)) {
                    if ($src.PSObject.Properties['provider_and_id'] -and
                        $src.provider_and_id -match 'WindowsUpdateClient/20') {
                        $wuClientHits = [int]$src.count
                        break
                    }
                }
                if ($wuClientHits -lt 5) { return $null }

                @{
                    target = $wu
                    partner = $ev
                    note_primary = "related: event-log-errors has $wuClientHits WUClient/20 install failures"
                    note_partner = 'related: windows-update reports reboot pending'
                    upgrade_primary_to = 'WARN'
                }
            }
        }
    )
}

function Invoke-FindingCorrelation {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $CheckResults,
        [int] $MaxCorrelations = 5
    )

    if ($CheckResults.Count -eq 0) { return $CheckResults }

    $severityOrder = @{ 'OK' = 0; 'INFO' = 1; 'WARN' = 2; 'CRIT' = 3; 'UNKNOWN' = 99 }
    $applied = 0

    foreach ($rule in Get-CorrelationRule) {
        if ($applied -ge $MaxCorrelations) { break }
        $match = & $rule.Apply $CheckResults
        if ($null -eq $match) { continue }

        # Upgrade severity only (never downgrade).
        if ($match.upgrade_primary_to) {
            $currentSev = $match.target.severity
            $newSev = $match.upgrade_primary_to
            if ($severityOrder[$newSev] -gt $severityOrder[$currentSev]) {
                $match.target.severity = $newSev
            }
        }

        # Cross-link notes: additive.
        if ($match.note_primary) {
            $existing = $match.target.notes
            $match.target.notes = $existing ? "$existing; $($match.note_primary)" : $match.note_primary
        }
        if ($match.note_partner) {
            $existing = $match.partner.notes
            $match.partner.notes = $existing ? "$existing; $($match.note_partner)" : $match.note_partner
        }

        $applied++
    }

    return $CheckResults
}
