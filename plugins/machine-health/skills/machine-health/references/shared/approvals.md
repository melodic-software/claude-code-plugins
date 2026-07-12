# Approvals and per-user state

User-specific approval state lives at `<StateBase>/state/approvals.json` — **not** in the plugin's shipped `TODO.md`. The skill ships with defaults (nothing approved); the user enables individual remediations via `/machine-health:setup` or by editing the JSON directly.

Schema: [`catalog/schemas/approvals.schema.json`](../../catalog/schemas/approvals.schema.json).

## Why it lives under the state root, not in the plugin

`<StateBase>` (the plugin data directory, `${CLAUDE_PLUGIN_DATA}`) is the per-machine root for state and logs — it survives plugin updates, while the plugin install directory is replaced by them. Approvals are per-machine config, not policy — they belong next to other machine-local artifacts.

The previous design put checkboxes in a tracked `TODO.md` inside the skill directory. That design had three problems:

1. **Source control pollution.** Every approval was a commit. Multiple hosts sharing the same checkout collided.
2. **No schema.** `[x]` boxes rely on regex parsing. A typo silently disables the approval with no error.
3. **Global state.** Approvals applied to every host, every user, every workspace that checked out the repo.

`approvals.json` solves all three. Outside the plugin, schema-validated, scoped to this machine's state root.

## What `TODO.md` is now

`TODO.md` shipped with the plugin is **policy documentation**, not state. It lists remediations available for approval, their risks, and how to enable them. Never contains checkboxes that drive behavior. Runtime proposals accumulate in `<StateBase>/TODO.md`.

## Enabling a remediation

Default state: both shipped remediations start as `approved: false`. Enable by editing `approvals.json`:

```json
{
  "schema_version": "1.0",
  "remediations": {
    "clear-temp-files": {
      "approved": true,
      "approved_at": "2026-04-22T17:30:00-04:00",
      "approved_by": "<user>@<hostname>",
      "notes": "Enabled after reviewing first dry-run report."
    },
    "restart-stopped-service": {
      "approved": false,
      "notes": "Still reviewing which services are safe to auto-restart."
    }
  }
}
```

The orchestrator reads this on every run. No restart, no cache invalidation — file is re-read per invocation.

## Migration from `TODO.md` (one-time)

On first run after upgrade from the legacy in-repo skill, if `approvals.json` is **missing or empty** and a `TODO.md` contains `[x]` checkboxes, the orchestrator:

1. Parses TODO.md for checked approvals (best-effort — only recognizes the two known remediation names).
2. Writes `approvals.json` with migrated approvals and a `migration.migrated_from_todo_md: true` marker plus a checksum of the source TODO.md.
3. Logs the migration to `<StateBase>/logs/run-YYYY-MM-DD.log`.
4. Continues the run normally using migrated approvals.

On subsequent runs, TODO.md checkboxes are ignored entirely. The `migration` block is informational only.

After the next major version of the plugin, TODO.md parsing is removed.

## First-run behavior (unchanged from prior design)

`RunMode = first-run` still forces `DryRun = $true`. Approvals read normally but no remediation executes. First-run produces a baseline report the user can review before approving anything.

## Revoking an approval

Flip `approved: true` to `false`. Next run respects it immediately. No cache.

## Per-host check overrides

The optional `check_overrides` block carries per-host user curation:

- `event-log-errors.noise_allowlist` - additional benign provider+id pairs to suppress beyond the shipped list.
- `services.service_exclusions` - service names never touched by `Restart-StoppedService`.

Shipped lists always take precedence; user lists augment them.

## Testing

Pester tests in `tests/windows/lib/Get-ApprovalState.Tests.ps1` cover:

- Missing file - returns defaults (nothing approved)
- Empty file - returns defaults
- Schema-invalid file - logs warning, returns defaults, does not throw
- Valid file - returns parsed approvals
- Migration path: TODO.md `[x]` present, no approvals.json - migrates, writes file, logs
- Revocation: edit file, re-read, respects new state

## Open follow-ups

- Signed approvals (HMAC or signed JSON) - not in v1; approvals.json integrity relies on filesystem permissions.
- Cross-host approvals (e.g., "approve on every workstation in this domain") - not in scope. This skill is single-host.
- TODO.md removal timeline - after version 2.0 of the plugin.
