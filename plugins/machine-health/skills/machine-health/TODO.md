# machine-health — TODO and approval policy

> **This file holds no state.** Approval state lives at `<StateBase>/state/approvals.json` (machine-local, under the plugin data directory). Runtime proposals accumulate in `<StateBase>/TODO.md`, not here. See [`references/shared/approvals.md`](references/shared/approvals.md) for the full design.

## Approvable remediations (Windows)

Policy details: [`references/windows/remediation-policy.md`](references/windows/remediation-policy.md).

| Id | Action | Default | Risk posture |
|---|---|---|---|
| `restart-stopped-service` | One `Start-Service` per stopped Automatic service | `approved: false` | Low. One attempt per service per run. Before/after state logged. |
| `clear-temp-files` | Delete files older than 7 days from `$env:TEMP`, `$env:LOCALAPPDATA\Temp`, `C:\Windows\Temp` | `approved: false` | Low. Reparse points skipped. User profile files outside temp paths not touched. |

To enable, run `/machine-health:setup`, or edit `<StateBase>/state/approvals.json` directly:

```json
{
  "schema_version": "1.0",
  "remediations": {
    "restart-stopped-service": { "approved": true, "notes": "Reviewed first dry-run report 2026-04-22." },
    "clear-temp-files": { "approved": true, "notes": "Enabled after verifying temp paths." }
  }
}
```

Revoke by flipping `approved` to `false`. Re-read per run; no restart needed.

## Explicitly not authorized

Per [`references/windows/remediation-policy.md`](references/windows/remediation-policy.md):

- Windows Update cache clear — not authorized at any approval level. If you need this, run the commands manually.
- Driver reinstall / rollback — not authorized.
- Defender signature force-update — not authorized.
- Registry cleanup, network stack resets, service configuration changes, reboots — not authorized.

Adding new remediations requires editing the remediation policy file (shipped with the plugin), the approvals schema (if new fields are needed), and orchestrator dispatch wiring — a plugin change with a version bump.
