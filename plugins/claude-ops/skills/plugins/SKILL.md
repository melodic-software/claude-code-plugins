---
description: "Bring a machine's plugin fleet current on demand: marketplace refresh, update the plugins that actually load (including in-repo project/local-scope installs), install new catalog plugins per policy, detect scope divergence, and surface (never silently fix) drift — with a terse actionable report. Actions: sync (default, mutating), audit (read-only dry run), converge (explicit scope consolidation). Use when: 'sync plugins', 'update my plugins', 'are my plugins current', 'check plugin drift', 'converge plugin scopes', or before relying on a plugin that might be stale."
argument-hint: "[action] [<marketplace>|all] — actions: sync (default), audit, converge"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: operator
  summary: Bring the machine's plugin fleet current — refresh, update, install per policy
  cadence: weekly
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

**Never silently fixes drift it finds.** `sync` mutates only via the documented CLI actions below,
and never writes a committed `.claude/settings.json`: its Step 5 enables automatically only at
`user` and `local` scope, and reports a `project`-scope gap rather than filling it, because `sync`
has no autonomous-session abort behind which a confirm would mean anything. `converge` is the one
action that can touch committed settings, and only after an explicit per-plugin confirm. See
[context/scope-semantics.md](context/scope-semantics.md) for which CLI calls write that file.

## Action Router

Parse `$ARGUMENTS` for the action (first token) and an optional marketplace target (second token:
a marketplace name, or `all`).

This table is an index, not a substitute: read the linked detail file before executing any action.
Each Description names the territory an action covers, never its algorithm — the steps, their
ordering, and their failure handling live only in the linked file.

| Action | Mutates | Description | Detail |
|---|---|---|---|
| `sync` (default) | Yes — CLI only | Marketplace, install, and enable-state maintenance for the effective fleet | [context/sync.md](context/sync.md) |
| `audit` | No | Same algorithm as `sync`, every mutating step replaced with a prediction; issues zero mutating CLI calls | "Action: audit" below |
| `converge` | Yes — can rewrite committed settings after confirm | Cross-scope divergence reconciliation, preview- and confirm-gated | [context/converge.md](context/converge.md) |

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
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh [--marketplace <name>] --ids <selector>
```

The second form emits the plain id list a mutating step loops, instead of the JSON report — one
tab-separated record per line, first field always the fully-qualified `<name>@<marketplace>`. Use it
whenever a step needs ids; never hand-write a `jq` extraction over the JSON, which reintroduces a
trailing `\r` on Windows and silently corrupts every id but the last (see
[context/gotchas.md](context/gotchas.md)).

Read [context/scope-semantics.md](context/scope-semantics.md) before interpreting its output — in
particular its "Divergence is not automatically actionable" section, the normative statement of the
`versionsMatch` filter rule that every divergence count this skill reports must apply.

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
In-repo: <N> updated | none — project context <root>, no in-repo installs | none — no project
  context (Step 2 did not apply)
Updated: <N> plugin(s) — <id>@<marketplace>: <old> → <new> (only when N > 0)
Installed: <N> new catalog plugin(s) — <id>@<marketplace> (only when N > 0; per install_new policy)
Note: claude-ops updated mid-run (<old> → <new>); this run executed the <old> algorithm
  (only when the sweep updated claude-ops@<marketplace> itself — see context/sync.md)
Divergences: <N> project-scope install(s) behind user scope → run `/claude-ops:plugins converge`
  (N = the actionable subset per scope-semantics.md's versionsMatch filter rule)
Action needed: <bulleted list — missing_from_user_install, missing_from_enabled, project-scope
  enable gaps, orphaned install records, CLI failures, unknown plugins> (omit section entirely
  when empty)
```

The `In-repo:` row is **always present**, in exactly one of its three states — the deliberate
exception to "only rows needing action." Step 2 of [context/sync.md](context/sync.md) is the
primary value path, and its silent no-op was invisible precisely because the row's absence looked
identical to "ran and found nothing": `fleet-state.sh`'s `project_root` disambiguates the two
zero-record states (null → the step did not apply; non-null → it ran against `<root>` and found no
in-repo installs), and sync.md Step 2 fixes which state maps to which wording.

The `Note:` row appears only when the sweep updated `claude-ops@<marketplace>` itself. The skill
content rendered for this session — the algorithm that actually ran — is the pre-update version,
so the report must never imply the new version's algorithm produced it (see
[context/sync.md](context/sync.md) "Self-update").

A project-scope enable gap is a row `sync` deliberately does not fix — Step 5 enables automatically
only where the write is not team-shared state. Give each one its runnable command rather than a
count, so acting on it is a copy, not a reconstruction:

```text
- project-scope enable gap: (cd "<projectPath>" && claude plugin enable <id>@<marketplace> -s project)
  — writes that repo's committed .claude/settings.json; review the diff before committing
```

Emit that command only when the record's `projectPathExists` is `true`. A `false` record's
directory is gone, so the command can only fail — the row moves to the orphaned-install-record
category below instead. Only ids that Step 5 did not enable at `user`/`local` scope in this run
appear here — for the rest the command would fail rather than run, and Step 5 explains why.

An **orphaned install record** — an install record whose recorded `projectPath` no longer exists on
disk (`projectPathExists: false`) — is its own named "Action needed" category, and always
report-only: any `(cd "<projectPath>" && …)` command constructed against it can only fail, and no
CLI verb reaps such a record (observed on CC 2.1.240; `prune -s project` has the same no-path-flag
limitation as every `-s project` verb), so the record stays until upstream provides a reap path.
Name the id, scope, and dead path per row rather than a bare count.

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
explicitly set** in a `pluginConfigs` map Claude Code actually reads: since Claude Code v2.1.207
that is user scope (`~/.claude.json`, or the `--settings` file) and managed settings only —
project- and local-scope `pluginConfigs` are ignored, unlike `enabledPlugins`, which this same
skill reads and which still honors project/local scope. Declaring the option in `plugin.json` alone
does not make its value readable here. Crucially, the manifest's `"default": "ask"` is **not**
substituted for an unset key (verified 2026-07-23 against CC 2.1.218: an unset key leaves the placeholder token
unchanged — the same shape as `${user_config.…}` — while a sibling `${CLAUDE_PLUGIN_ROOT}` substitutes
in the same render). So for the common default-config user — no `pluginConfigs` set anywhere — the
**Configured value** line above still shows that literal placeholder token, not `ask`.

Read that literal placeholder token as the **expected unset state → use the default `ask`**, and do NOT
report it as an invalid value. Only a rendered value that is a real word other than
`ask`/`all`/`none` (i.e. the key *was* set, to something unsupported) is the invalid-value case worth
flagging. Sync's Step 4 branches on the **Configured value** line's rendered value — or on the `ask`
default when that render is still the placeholder token — not on the option's name or description above.

## Cross-references

- [context/sync.md](context/sync.md) — full `sync` algorithm
- [context/converge.md](context/converge.md) — scope-consolidation flow, confirm gate, autonomous-session abort
- [context/scope-semantics.md](context/scope-semantics.md) — verified CC scope/version/reload facts this skill depends on
- [context/gotchas.md](context/gotchas.md) — known failure modes and how this skill avoids them
