# Approvals and per-user state

User-specific approval state lives at `<StateBase>/state/approvals.json`, **not** in the plugin's shipped `TODO.md`. The skill ships with defaults (nothing approved); the user enables individual remediations via `/machine-health:setup`.

Schema: [`catalog/schemas/approvals.schema.json`](../../catalog/schemas/approvals.schema.json).

## Why it lives under the state root, not in the plugin

`<StateBase>` (the plugin data directory, `${CLAUDE_PLUGIN_DATA}`) is the per-machine root for state and logs, and it survives plugin updates, while the plugin install directory is replaced by them. Approvals are per-machine config, not policy, so they belong next to other machine-local artifacts.

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

## Writing approvals and mutes

`approvals.json` and `mutes.json` have one writer, `Set-ApprovalState`, which
`/machine-health:setup apply` runs (`approve=`, `revoke=`, `unmute=`). The one-time TODO.md migration below is the only other path that writes `approvals.json`,
and it never overwrites an existing file. Both go through the same atomic replace.

What a write guarantees:

- A reader sees the old file or the new one, never a partial write, and a reader never blocks it.
- Concurrent writers are serialized by `<StateBase>/state/approvals.lock`: a second writer waits and
  applies its change to the file the first one wrote.
- The result is validated against the file's schema before it replaces anything; an invalid result
  leaves the file as it was.
- Nothing is written when a OneDrive variable names `<StateBase>` or a folder above it.

Hand edits of `approvals.json` or `mutes.json` are unsupported while an audit or setup session
runs: the lock covers the plugin's writers, not an editor, so a hand edit can be overwritten or can
overwrite a change made at the same moment.

## Enabling a remediation

Default state: both shipped remediations start as `approved: false`. Enable one with
`/machine-health:setup apply approve=<remediation-id>`, which writes an entry like these:

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

The orchestrator reads this on every run. No restart, no cache invalidation: the file is re-read per invocation.

## Migration from `TODO.md` checkboxes (one-time)

When `approvals.json` is **missing or empty** and a `<StateBase>/TODO.md` contains
`[x]` checkboxes, the orchestrator:

1. Parses TODO.md for checked approvals (best-effort, recognizing only the two known remediation names).
2. Writes `approvals.json` with migrated approvals and a `migration.migrated_from_todo_md: true` marker plus a checksum of the source TODO.md.
3. Logs the migration to `<StateBase>/logs/run-YYYY-MM-DD.log`.
4. Continues the run normally using migrated approvals.

On subsequent runs, TODO.md checkboxes are ignored entirely. The `migration` block is informational only.

This path exists only to carry a checkbox-era approval forward once. Retiring it is a plugin
change recorded in `CHANGELOG.md`, not a condition this file predicts.

## First-run behavior

`RunMode = first-run` still forces `DryRun = $true`. Approvals read normally but no remediation executes. First-run produces a baseline report the user can review before approving anything.

## Revoking an approval

`/machine-health:setup apply revoke=<remediation-id>` sets `approved` to `false` and refreshes
`approved_at`. The next run respects it immediately. No cache.

## Per-host check overrides

The optional `check_overrides` block carries per-host user curation. The one key read is
`services.service_exclusions`: service names `Restart-StoppedService` never starts. A name
matches when it equals the service name, ignoring case; the run log records each skip. Setup
cannot write this list yet, so it is the one key in `approvals.json` the owner edits by hand.

The schema still accepts `event-log-errors.noise_allowlist` so an older file validates, but no
check reads it.

## Finding mutes (`mutes.json`)

Muted finding items live in their own file, `<StateBase>/state/mutes.json`, beside
`approvals.json`; mutes never go in `approvals.json`. Schema:
[`catalog/schemas/mutes.schema.json`](../../catalog/schemas/mutes.schema.json).

```json
{
  "schema_version": "1.0",
  "checks": {
    "browser-extensions": {
      "muted_findings": [
        { "key": "ext:3f9a0c1d2e4b5a67", "label": "<item title>", "reason": null,
          "added_at": "2026-10-21T12:00:00Z", "run_id": "<latest.json run_id>" }
      ]
    }
  }
}
```

- The entry fields are defined by the schema; `key` is the item's FindingKey and the item shape
  is in [`output-schema.md`](output-schema.md#detail-of-a-list-style-check-findingitems).
- The orchestrator reads the file with `Get-MuteState` (`scripts/windows/lib/Get-MutedFindingKey.ps1`)
  and passes each check that declares `-MutedKeys` its muted keys. Checks never read `mutes.json`.
- The read creates nothing, migrates nothing and writes no log. A missing, empty, malformed or
  schema-invalid file means no mutes; a broken file warns and is left as it is.
- `Get-ApprovalState` and `Get-MuteState` read through `Read-SharedText`
  (`FileShare.ReadWrite | FileShare.Delete`), so a writer replacing the file never blocks a run.
- A plugin build older than `mutes.json` ignores the file: muted items count toward severity again
  until the upgrade. Nothing FAILs and nothing is stripped.

## Testing

Pester tests in `tests/windows/lib/Get-ApprovalState.Tests.ps1` cover:

- Missing file - returns defaults (nothing approved)
- Empty file - returns defaults
- Schema-invalid file - logs warning, returns defaults, does not throw
- Valid file - returns parsed approvals
- Migration path: TODO.md `[x]` present, no approvals.json - migrates, writes file, logs
- Revocation: edit file, re-read, respects new state
- Shared read: succeeds while another handle holds the file for write
- The migration writes through `Write-StateFile` and never overwrites a file that appeared meanwhile

`tests/windows/lib/Write-StateFile.Tests.ps1` covers the replace recipe and its sharing and
first-write cases; `tests/windows/lib/Set-ApprovalState.Tests.ps1` covers each action, the
refusals, the schema check before the replace, the `approvals.lock` wait and the synced
`<StateBase>` refusal.

`tests/windows/lib/Get-MutedFindingKey.Tests.ps1` covers `mutes.json`: the schema, the per-check
key lookup, the fail-safe fallbacks, the shared read, and that the read creates no file or folder.
`tests/windows/lib/Read-SharedText.Tests.ps1` covers the shared open, including a holder with
delete access.

## Known limits

- Approvals are not signed. `approvals.json` integrity relies on filesystem permissions.
- Cross-host approvals ("approve on every workstation in this domain") are out of scope. This
  skill is single-host.
