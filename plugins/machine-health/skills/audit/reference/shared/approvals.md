# Approvals and per-user state

User-specific approval state lives at `<StateBase>/state/approvals.json` — **not** in the plugin's shipped `TODO.md`. The skill ships with defaults (nothing approved); the user enables individual remediations via `/machine-health:setup` or by editing the JSON directly.

Schema: [`catalog/schemas/approvals.schema.json`](../../catalog/schemas/approvals.schema.json).

## Why it lives under the state root, not in the plugin

`<StateBase>` (the plugin data directory, `${CLAUDE_PLUGIN_DATA}`) is the per-machine root for state and logs — it survives plugin updates, while the plugin install directory is replaced by them. Approvals are per-machine config, not policy — they belong next to other machine-local artifacts.

Three properties make this the right home:

1. **No source-control pollution.** An approval is machine-local state, so it never becomes a
   commit and two hosts sharing a checkout never collide.
2. **Schema-validated.** `approvals.schema.json` catches a malformed entry. A checkbox parsed out
   of markdown fails silently on a typo.
3. **Scoped to this host.** Approvals apply to this machine's state root, not to every host that
   checks out the repository.

## What the shipped `TODO.md` is

The `TODO.md` shipped with the plugin is **policy documentation**, not state. It lists
remediations available for approval, their risks, and how to enable them. It contains no
checkbox that drives behavior. Runtime proposals accumulate in `<StateBase>/TODO.md`.

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

## Migration from `TODO.md` checkboxes (one-time)

When `approvals.json` is **missing or empty** and a `TODO.md` in the skill directory contains
`[x]` checkboxes, the orchestrator:

1. Parses TODO.md for checked approvals (best-effort — only recognizes the two known remediation names).
2. Writes `approvals.json` with migrated approvals and a `migration.migrated_from_todo_md: true` marker plus a checksum of the source TODO.md.
3. Logs the migration to `<StateBase>/logs/run-YYYY-MM-DD.log`.
4. Continues the run normally using migrated approvals.

On subsequent runs, TODO.md checkboxes are ignored entirely. The `migration` block is informational only.

This path exists only to carry a checkbox-era approval forward once. Retiring it is a plugin
change recorded in `CHANGELOG.md`, not a condition this file predicts.

## First-run behavior

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

## Known limits

- Approvals are not signed. `approvals.json` integrity relies on filesystem permissions.
- Cross-host approvals ("approve on every workstation in this domain") are out of scope. This
  skill is single-host.
