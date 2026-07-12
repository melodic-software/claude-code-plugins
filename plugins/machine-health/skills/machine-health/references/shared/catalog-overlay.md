# Catalog overlay — machine-local check customization

The shipped catalog (`catalog/checks.jsonc`) is read-only at runtime: it lives inside the
installed plugin, and a plugin update replaces it. Everything machine-specific about the
catalog goes in an **overlay file** under the state base:

```text
<StateBase>/catalog/checks.local.jsonc
```

`<StateBase>` is the state root the orchestrator resolves (explicit `-StateBase` parameter,
then `CLAUDE_PLUGIN_DATA`, then `-OutputBase`). `/machine-health:setup` writes this file;
hand-editing is also fine — it is re-read on every run.

## Shape and merge semantics

Same JSONC shape as the shipped catalog: `{ "checks": [ ... ] }`. Merged by `id`:

| Overlay entry | Effect |
|---|---|
| `id` matches a shipped check | The overlay's properties override that entry's (partial entries are fine — list only the fields to change) |
| `id` is new | Appended as a custom check (full schema-valid entry required) |

Entries are never deleted by an overlay — set `"enabled": false` to turn a check off, or
`"deprecated": true` + `"deprecation_reason"` to retire it with history continuity. Every
merged entry is schema-validated; an invalid one is skipped with a log warning and the rest
of the catalog still runs.

## Common patches

```jsonc
{
  "checks": [
    // Disable a shipped check on this host
    { "id": "battery", "enabled": false },

    // Demote a chronically quiet check to monthly cadence. On a weekly run the
    // orchestrator skips a monthly check that ran within the last ~4 weeks
    // (per-check last run tracked in state/history.jsonl); on-demand and
    // first-run always run every enabled check.
    { "id": "cert-expiry", "cadence": "monthly" },

    // Retire a check that is meaningless for this host
    {
      "id": "container-disk-usage",
      "deprecated": true,
      "deprecation_reason": "No container runtime on this machine (2026-07-12)."
    }
  ]
}
```

## Custom checks

A custom check keeps the standard `scripts/<os>/checks/Name.ps1` path shape but lives under
the state base — the orchestrator resolves a check script against the plugin first, then
against `<StateBase>`:

1. Write the check to `<StateBase>/scripts/windows/checks/Test-MyThing.ps1`, emitting a
   single JSON object per `references/shared/output-schema.md` (`-Human` mode included, per
   the dual-invocation convention).
2. Register it in the overlay with a full catalog entry (`script` set to
   `scripts/windows/checks/Test-MyThing.ps1`).

Custom checks run under the same per-check timeout, trend analysis, and severity rules as
shipped ones.

## Relation to self-improvement

The skill's self-improvement loop (deprecation proposals, cadence demotions) writes its
*proposals* to `<StateBase>/TODO.md` for human approval; approved changes are then applied
to this overlay — never to the shipped catalog.
