# Design resolution — plugin-fleet-sync-skill

outcome: early-exit (Tier B)

Reason: the contract surface was fully resolved by the /interview Brief (PLAN.md `## Brief`,
Decisions 1–8) backed by three verified research passes (official CC docs, repo conventions,
scope-precedence empirics). No new code types or module topology — the deliverable is a
markdown skill orchestrating the `claude plugin` CLI plus one read-only state-inspection
script. Type surface is small enough to sketch here; full /design would re-derive the Brief.

## Type sketch

**Action surface** (router in SKILL.md):

- `sync [marketplace|all]` — default; mutating via CLI only
- `audit [marketplace|all]` — read-only dry-run of sync + converge predictions
- `converge` — explicit scope consolidation; only committed-settings-touching action

**userConfig** (plugin.json, personal policy scalar):

- `install_new`: `ask` (default) | `all` | `none` — enum support in the manifest schema is a
  Phase-1 verification; fallback is a string field validated in skill prose.

**State-inspection output** (read-only script → JSON consumed by the skill):

```json
{
  "marketplace": {"name": "...", "autoUpdate": false, "lastUpdated": "..."},
  "catalog": ["plugin", "..."],
  "installed": [{"id": "plugin@mp", "scope": "user|project|local", "version": "...", "projectPath": "..."}],
  "enabled": {"plugin@mp": true},
  "missing_from_install": ["..."],
  "missing_from_enabled": ["..."],
  "divergences": [{"id": "...", "scopes": [{"scope": "...", "version": "...", "projectPath": "..."}]}]
}
```

Inputs are internal CC state files read-only (`installed_plugins.json`, `known_marketplaces.json`,
marketplace `marketplace.json`, settings `enabledPlugins`); every mutation goes through the CLI.
