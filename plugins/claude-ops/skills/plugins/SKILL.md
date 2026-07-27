---
name: plugins
description: "Bring a machine's plugin fleet current on demand: marketplace refresh, update the plugins that actually load (including in-repo project/local-scope installs), install new catalog plugins per policy, detect scope divergence, and surface (never silently fix) drift — with a terse actionable report. Actions: sync (default, mutating), audit (read-only dry run), converge (explicit scope consolidation). Use when: 'sync plugins', 'update my plugins', 'are my plugins current', 'check plugin drift', 'converge plugin scopes', or before relying on a plugin that might be stale."
argument-hint: "[action] [<marketplace>|all] — actions: sync (default), audit, converge"
user-invocable: true
disable-model-invocation: true
metadata:
  cheatsheet-stage: operator
  cheatsheet-summary: Bring the machine's plugin fleet current — refresh, update, install per policy
  cheatsheet-cadence: weekly
---

## Variables

Arguments: `$ARGUMENTS`

## Scope

Guarantees that the plugins which actually load — for the machine's user scope, and for any repo
you're standing in with its own project/local-scope installs — are the latest published versions of
everything the marketplace offers, and surfaces any state where something older or unintended is
what really runs.

Distinct from what Claude Code's own background `autoUpdate` does (see
[context/scope-semantics.md](context/scope-semantics.md)): `autoUpdate` silently refreshes marketplace
data and bumps already-installed plugins post-startup. It never installs a new catalog plugin, never
checks `enabledPlugins` completeness, never detects or reports scope divergence, and only runs once
per session start on its own schedule — not on demand. This skill covers exactly that gap.

Distinct from `claude-config`'s `audit` skill's plugin-drift check: that check compares a project's
committed `enabledPlugins` against a marketplace's *upstream* `marketplace.json` (orphan/new/rename
plugin names). This skill compares the *local, already-installed* state (`installed_plugins.json`,
per-scope `enabledPlugins`) against the *local* marketplace catalog — a different axis (install/scope
completeness, not settings-vs-upstream drift).

**Never silently fixes drift it finds.** `sync` mutates only via the documented CLI actions below;
`converge` is the one action that can touch a committed `.claude/settings.json`, and only after an
explicit per-plugin confirm.

## Action Router

Parse `$ARGUMENTS` for the action (first token) and an optional marketplace target (second token:
a marketplace name, or `all`).

| Action | Mutates | Description | Detail |
|---|---|---|---|
| `sync` (default) | Yes — CLI only | Marketplace refresh → in-repo update → user-scope update sweep → install new per policy → enabledPlugins completeness → report | [context/sync.md](context/sync.md) |
| `audit` | No | Same algorithm as `sync`, every mutating step replaced with a prediction; issues zero mutating CLI calls | "Action: audit" below |
| `converge` | Yes — the one action that can touch committed settings | Detects any plugin id with an actionable (non-benign) scope divergence, previews per-plugin intent, confirms, executes, surfaces the resulting diff | [context/converge.md](context/converge.md) |

Bare invocation (no arguments) → `sync` against the default marketplace. `help` or an unrecognized
action → show this table.

## Marketplace resolution

No hardcoded marketplace name anywhere in this skill. Every action resolves its target the same way:

- No marketplace argument → the default: the marketplace this plugin (`claude-ops`) was itself
  installed from, resolved dynamically by `fleet-state.sh` (joins `${CLAUDE_PLUGIN_ROOT}` against
  `installed_plugins.json`'s install records — never a hardcoded name).
- `<marketplace-name>` argument → that marketplace only.
- `all` argument → every marketplace in `known_marketplaces.json`; per-marketplace failures are
  reported inline and never abort the sweep (see [context/sync.md](context/sync.md)).

## State inspection

Every action starts by calling the bundled read-only script — never hand-parse the internal JSON
files directly, and never write them:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh [--marketplace <name> | --all]
```

Read [context/scope-semantics.md](context/scope-semantics.md) before interpreting its output — in
particular, `divergences[].versionsMatch` separates a benign same-version multi-scope install
(normal, no action) from a real version skew (the actionable "run converge" signal); a raw
divergence-record count conflates the two and overstates the report.

## Action: audit

Read-only dry run of what `sync` (and, where relevant, `converge`) would do. Run the full algorithm
in [context/sync.md](context/sync.md) with every mutating CLI call replaced by "would run: `<command>`"
in the report — call `fleet-state.sh`, compute the same install/enable/divergence deltas, but issue
**zero** `plugin install|update|uninstall|marketplace update` invocations. Predict `converge`'s
per-plugin intent (context/converge.md's preview step) the same way, without executing it. State-file
contents (`installed_plugins.json`, `known_marketplaces.json`, committed settings) are unchanged by
an `audit` run, modulo any concurrent session or background `autoUpdate` sweep — note that caveat in
the report rather than asserting byte-identical files.

## Report

Terse, fixed sections. Detail only where action is required — do not enumerate rows that need no
action.

```text
Marketplace: <name> — <current | needs update> (autoUpdate: <on|off — suggest enabling if off>)
Updated: <N> plugin(s) — <id>@<marketplace>: <old> → <new> (only when N > 0)
Installed: <N> new catalog plugin(s) — <id>@<marketplace> (only when N > 0; per install_new policy)
Divergences: <N> project-scope install(s) behind user scope → run `/claude-ops:plugins converge`
  (N = actionable only — versionsMatch:false; same-version multi-scope installs are not counted
  or listed here)
Action needed: <bulleted list — missing_from_user_install, missing_from_enabled, CLI failures,
  unknown/orphaned plugins> (omit section entirely when empty)
```

When running inside a project (`CLAUDE_PROJECT_DIR` set and `fleet-state.sh`'s `installed[]` entries
carry `currentProject: true`), lead the Divergences line with *this* project's actionable count and
fold the rest of the machine into one trailing clause — e.g. `2 behind here → converge; 27 more
elsewhere on this machine`. Per-row detail (naming exact `<old> → <new>` versions per repo) is
reserved for genuine conflicts: an unknown/orphaned plugin id, or a CLI call that failed — never for
the routine bulk case. (Enable-state mismatches — a plugin `true` in one scope's `enabledPlugins`
and `false` in another — are a known blind spot, not a reportable category: `fleet-state.sh` only
exposes the merged effective value, never each scope's raw map, so this skill cannot detect one to
report it. See [context/converge.md](context/converge.md) "V1 scope".)

Close with reload guidance: recommend bare `/reload-plugins` by default; suggest `--force` only when
an updated/installed component ships an MCP server whose tools aren't deferred — that's the one case
`/reload-plugins` itself warns about and declines to apply without it (Claude Code ≥ 2.1.163; see
[context/scope-semantics.md](context/scope-semantics.md)). If any updated component includes a
monitor, call that out separately — monitors need a full session restart, `/reload-plugins` doesn't
cover them.

## userConfig: `install_new`

Controls new-catalog-plugin install policy during `sync`. Ships as a plain `string` (the manifest
schema has no `enum` type — verified against the published schema), default `"ask"`:

- `ask` (default) — offer every not-yet-installed catalog plugin in one batched multi-select prompt
- `all` — install every not-yet-installed catalog plugin automatically
- `none` — report them in "Action needed" only, never install

Any explicitly-set value other than these three is invalid; treat it as `ask` and note the invalid
value in the report.

**Configured value: `${user_config.install_new}`** — Claude Code text-substitutes a `userConfig`
value into this skill's content before the model sees the rendered skill, but **only when the key is
explicitly set** in some `pluginConfigs` scope; declaring the option in `plugin.json` alone does not
make its value readable here. Crucially, the manifest's `"default": "ask"` is **not** substituted for
an unset key (verified 2026-07-23 against CC 2.1.218: an unset key renders the literal placeholder,
while a sibling `${CLAUDE_PLUGIN_ROOT}` substitutes in the same render). So for the common
default-config user — no `pluginConfigs` set anywhere — this line renders as the **literal
placeholder text** `${user_config.install_new}`, unchanged.

Read that literal placeholder as the **expected unset state → use the default `ask`**, and do NOT
report it as an invalid value. Only a rendered value that is a real word other than
`ask`/`all`/`none` (i.e. the key *was* set, to something unsupported) is the invalid-value case worth
flagging. Sync's Step 4 branches on this line's rendered value — or on the `ask` default when the
render is the literal placeholder — not on the option's name or description above.

## Cross-references

- [context/sync.md](context/sync.md) — full `sync` algorithm
- [context/converge.md](context/converge.md) — scope-consolidation flow, confirm gate, autonomous-session abort
- [context/scope-semantics.md](context/scope-semantics.md) — verified CC scope/version/reload facts this skill depends on
- [context/gotchas.md](context/gotchas.md) — known failure modes and how this skill avoids them
