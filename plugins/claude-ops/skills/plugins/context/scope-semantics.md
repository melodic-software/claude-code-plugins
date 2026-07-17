# Scope semantics — verified facts this skill depends on

Every claim below was verified against a fetched official-docs page or an empirical test on a real
machine during this skill's implementation, not assumed from training data. Re-verify against
`code.claude.com/docs/en/plugins-reference` and `discover-plugins` if Claude Code's plugin CLI
changes shape.

## Scope-by-cwd loading

A plugin loads for a given working directory using scope precedence **local > project > user**:

| Scope | Settings file | Written by |
|---|---|---|
| `user` | `~/.claude/settings.json` | `claude plugin install\|update -s user` (default scope) |
| `project` | `<project-root>/.claude/settings.json` | `claude plugin install\|update -s project` — committed, team-shared |
| `local` | `<project-root>/.claude/settings.local.json` | `claude plugin install\|update -s local` — gitignored, personal |
| `managed` | Managed settings (enterprise) | Administrators only — this skill reports, never mutates |

`installed_plugins.json` (`~/.claude/plugins/installed_plugins.json`) can hold multiple install
records for the same `<plugin>@<marketplace>` id — one per scope, each with its own `version`. This
is normal, not a defect: a project can legitimately pin a different version than your personal user
scope. The record that actually loads for a given directory is the one at the *highest-precedence
scope present*, never simply "the newest version installed."

## Divergence is not automatically actionable

`fleet-state.sh`'s `divergences[]` lists every plugin id with more than one scope record, but tags
each with `versionsMatch`:

- `versionsMatch: true` — every scope pins the identical version. Benign, informational only. Do
  not count these toward a report's "N behind" line or list them under "Action needed."
- `versionsMatch: false` — scopes disagree on version. This is the actionable signal `sync`'s report
  surfaces and `converge` resolves.

A raw count of `divergences[].length` conflates the two and overstates drift — always filter on
`versionsMatch == false` before presenting a count to the user.

## `plugin list` / `plugin details` version output is misleading

**Verified misleading**: `claude plugin list` and `claude plugin details <name>` show the *highest
installed version across all scopes*, not the version actually loaded for the current working
directory. Never treat their output as "what's running here." Derive effective-version claims from
`fleet-state.sh`'s scope-by-cwd resolution (via `currentProject` + scope precedence) or a functional
probe — never from `list`/`details` text.

## `plugin update -s project` does NOT write committed settings

**Empirically verified** (hash-compared a real repo's `.claude/settings.json` and
`.claude/settings.local.json` before and after): `claude plugin update <id> -s project` updates only
the machine-local `installed_plugins.json` record. `enabledPlugins` carries no version — the
committed settings files are untouched by an update. `sync`'s in-repo update step is safe to run
without a settings-diff review; `converge`'s scope-*consolidation* is the one action that can add or
remove an `enabledPlugins` entry, and only that action surfaces a settings diff.

## `/reload-plugins` — bare by default, `--force` for the MCP-cache-invalidation case

**Verified against `code.claude.com/docs/en/discover-plugins`**: `/reload-plugins` refreshes skills,
agents, hooks, MCP, and LSP servers in-process. It does **not** cover monitors — a monitor requires a
full session restart. Recommend bare `/reload-plugins` by default; call out the restart requirement
only when an updated plugin ships a monitor.

`--force` is real (Claude Code ≥ 2.1.163), but scoped to one specific case: a plugin that provides an
MCP server whose tools aren't deferred by tool search invalidates the prompt cache on reload, and
`/reload-plugins` warns and does **not** apply the reload rather than eating that cost silently;
`--force` applies it anyway. Only suggest `--force` when the updated/installed component in this
sync's report actually ships such an MCP server (or the report already surfaced that warning) — never
recommend it by default alongside every reload, since it exists specifically to opt into a real token
cost the bare command declines to pay automatically.

## `userConfig` has no `enum` field

**Verified against the published plugin-manifest JSON Schema**: allowed `type` values are `string`,
`number`, `boolean`, `directory`, `file` — no `enum`. `install_new` ships as `type: string` with its
valid values (`ask`/`all`/`none`) documented in `description` and validated in prose by this skill,
not by the manifest schema.

## Renames are CC-native (≥ v2.1.193)

Claude Code rewrites a marketplace's `renames` map into installed/enabled state automatically at
session start (old id → new id; `null` means removal). This skill hard-codes no rename knowledge —
its only rename-adjacent behavior is that anything present in the current catalog but absent from
`installed_plugins.json` shows up as `missing_from_install`, which naturally covers a renamed
plugin's new id. `claude plugin prune` requires ≥ v2.1.121; renames mapping requires ≥ v2.1.193.

## `autoUpdate` is a background complement, not a substitute

Official-Anthropic marketplaces default `autoUpdate: true`; third-party and local-dev marketplaces
default it off (absent from `known_marketplaces.json`, not `false`). When on, Claude Code refreshes
marketplace data and bumps already-installed plugins once per session start, after a random delay of
up to ten minutes. This skill never mutates the setting — it only reports the marketplace's current
`autoUpdate` state and suggests enabling it when off, since it never overlaps with what this skill
covers (new-plugin install, `enabledPlugins` completeness, divergence detection/convergence,
deterministic on-demand execution).
