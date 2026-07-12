# Cross-finding correlation rules

When two or more check findings are symptoms of the same root cause, the
report should say so and severity should reflect the correlation. This
file defines the rules; `Invoke-FindingCorrelation.ps1` applies them.

Rules are cross-OS concepts (pending reboot + failing updates is the same
problem on macOS/Linux even though check ids differ). The ORCHESTRATOR
applies rules after check dispatch, before severity aggregation.

## Rule structure

Each rule is a PowerShell hashtable in `Get-CorrelationRules`:

```powershell
@{
    id       = 'wu-reboot-retry-loop'
    when     = @(
        @{ check_id = 'windows-update'; detail_key = 'reboot_pending'; detail_value = $true }
        @{ check_id = 'event-log-errors'; detail_key = 'top_sources'; min_count_provider_id = @('Microsoft-Windows-WindowsUpdateClient/20', 5) }
    )
    effect   = @{
        upgrade_severity = @{ check_id = 'windows-update'; to = 'WARN' }
        cross_link_note  = 'related: event-log-errors has WUClient/20 install failures'
    }
    rationale = '...'
}
```

## Active rules (v1)

1. **wu-reboot-retry-loop** - windows-update + event-log-errors
   - When: windows-update reports reboot_pending AND event-log-errors
     has >= 5 WindowsUpdateClient/20 events in last 7d
   - Effect: windows-update INFO -> WARN; cross-link note on both
   - Rationale: both findings are symptoms of the same failed-install
     plus reboot-pending cycle. Surfacing separately buries the pattern.

2. **ssd-wear-climbing** - disk-space + reliability (future)
   - When: disk-space reports wear_pct > 70 AND reliability reports
     stability_min_7d < 7
   - Effect: disk-space WARN -> CRIT; cross-link
   - Rationale: worn SSD + unstable system often precedes imminent failure.

3. **kev-plus-old-updates** - winget-upgrades + windows-update (future)
   - When: winget-upgrades reports kev_match_count > 0 AND
     windows-update reports reboot_pending
   - Effect: winget-upgrades severity is already CRIT; add note pointing
     at windows-update so user addresses both in one maintenance pass.

Only rule #1 is implemented in v1 to keep the framework honest. Add more as
recurring patterns surface in real reports.

## Non-goals

- No automatic remediation from correlation. Correlation refines severity
  and narrative; never triggers an action.
- No unbounded rule accumulation. Rules are additive; framework caps
  correlations at 5 per run to avoid a report buried in cross-links.
