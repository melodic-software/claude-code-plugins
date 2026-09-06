---
description: "Bring a machine's plugin fleet current on demand: marketplace refresh, update the plugins that actually load (including in-repo project/local-scope installs), install new catalog plugins per policy, detect scope divergence, and surface (never silently fix) drift, with a terse actionable report. Actions: sync (default, mutating), audit (read-only dry run), converge (explicit scope consolidation). Use when: 'sync plugins', 'update my plugins', 'are my plugins current', 'check plugin drift', 'converge plugin scopes', or before relying on a plugin that might be stale."
argument-hint: "[action] [<marketplace>|all]. Actions: sync (default), audit, converge"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: operator
  summary: Bring the machine's plugin fleet current. Refresh, update, install per policy
  cadence: weekly
---

## Variables

Arguments: `$ARGUMENTS`

## Scope

Guarantees that the plugins which actually load, for the machine's user scope, and for any repo
you're standing in with its own project/local-scope installs, are the latest published versions of
everything the marketplace offers, and surfaces any state where something older or unintended is
what really runs.

Distinct from what Claude Code's own background `autoUpdate` does (see
[context/scope-semantics.md](context/scope-semantics.md)): `autoUpdate` silently refreshes marketplace
data and bumps already-installed plugins post-startup. It never installs a new catalog plugin, never
checks `enabledPlugins` completeness, never detects or reports scope divergence, and only runs once
per session start on its own schedule, not on demand. This skill covers exactly that gap.

Distinct from `claude-config`'s `audit` skill's plugin-drift check: that check compares a project's
committed `enabledPlugins` against a marketplace's *upstream* `marketplace.json` (orphan/new/rename
plugin names). This skill compares the *local, already-installed* state (`installed_plugins.json`,
per-scope `enabledPlugins`) against the *local* marketplace catalog, a different axis (install/scope
completeness, not settings-vs-upstream drift).

**Never silently fixes drift it finds.** `sync` mutates only via the documented CLI actions below,
and never writes a committed `.claude/settings.json`: its Step 5 enables automatically only at
`user` and `local` scope, and reports a `project`-scope gap rather than filling it, because `sync`
has no autonomous-session abort behind which a confirm would mean anything. After Step 4 installs
anything, `sync` may reorder keys in user-scope `~/.claude/settings.json` (machine-local, already
written by `claude plugin install -s user`) so the map stays alphabetical; it never reorders a
project-scope map. `converge` is the one action that can touch committed settings, and only after
an explicit per-plugin confirm. See [context/scope-semantics.md](context/scope-semantics.md) for
which CLI calls write that file.

## Action Router

Parse `$ARGUMENTS` for the action (first token) and an optional marketplace target (second token:
a marketplace name, or `all`).

This table is an index, not a substitute: read the linked detail file before executing any action.
Each Description names the territory an action covers, never its algorithm, the steps, their
ordering, and their failure handling live only in the linked file.

Two blocks below are deliberate exceptions to that index-only rule, and both have to live in the hub
rather than in a spoke. The **Report** template, because every action emits it. The
**`install_new` render**, because Claude Code substitutes `${user_config.*}` when it renders the
*skill*; a spoke opened later as a file read is plain bytes, so the same token in a spoke would
arrive as a literal placeholder with no error to warn anyone. See
[context/gotchas.md](context/gotchas.md).

| Action | Mutates | Description | Detail |
|---|---|---|---|
| `sync` (default) | Yes. CLI only | Marketplace, install, and enable-state maintenance for the effective fleet | [context/sync.md](context/sync.md) |
| `audit` | No | Same algorithm as `sync`, every mutating step replaced with a prediction; issues zero mutating CLI calls | "Action: audit" below |
| `converge` | Yes. Can rewrite committed settings after confirm | Cross-scope divergence reconciliation, preview- and confirm-gated | [context/converge.md](context/converge.md) |

Bare invocation (no arguments) → `sync` against the default marketplace. `help` or an unrecognized
action → show this table.

## Marketplace resolution

No hardcoded marketplace name anywhere in this skill. Every action resolves its target the same way:

- No marketplace argument → the default: the marketplace this plugin (`claude-ops`) was itself
  installed from, resolved dynamically by `fleet-state.sh` (joins `${CLAUDE_PLUGIN_ROOT}` against
  `installed_plugins.json`'s install records, never a hardcoded name).
- `<marketplace-name>` argument → that marketplace only.
- `all` argument → every marketplace in `known_marketplaces.json`; per-marketplace failures are
  reported inline and never abort the sweep (see [context/sync.md](context/sync.md)).

## State inspection

Every action starts by calling the bundled read-only script, never hand-parse the internal JSON
files directly, and never write them:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh [--marketplace <name> | --all]
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh [--marketplace <name>] --ids <selector>
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh --ids <selector> --from <report.json>
```

The second form emits the plain id list a mutating step loops, instead of the JSON report. One
tab-separated record per line, first field always the fully-qualified `<name>@<marketplace>`. Use it
whenever a step needs ids; never hand-write a `jq` extraction over the JSON, which reintroduces a
trailing `\r` on Windows and silently corrupts every id but the last (see
[context/gotchas.md](context/gotchas.md)).

The third form projects that same id list from a report already on disk rather than recomputing the
fleet, and is the form `sync`'s steps use: each step re-reads the full report anyway, and every
selector is derivable from it. Same script, same projection, so the `\r` protection is unchanged.

A second read-only script answers the question `fleet-state.sh` structurally cannot: whether the
files in a plugin's cache directory actually match the commit its install record claims. Run it as
Step 5b of `sync` and of `audit`:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/cache-content-check.sh --marketplace <name> [--scope user|project|all]
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/cache-content-check.sh --marketplace <name> --ids
```

`--ids` emits the stale ids alone, one per line, CR-free, the same contract and for the same reason
as `fleet-state.sh --ids`. The script never writes anything and never runs `git fetch`; a commit
that is not in the local marketplace clone is reported as `sha-not-local`, not fetched. See
[context/sync.md](context/sync.md) Step 5b, and
[context/scope-semantics.md](context/scope-semantics.md) for the mechanism that makes a cache
directory and its recorded sha disagree in the first place.

`sync` writes its run journal under this plugin's per-machine data directory. The path is
substituted here because `${CLAUDE_PLUGIN_DATA}` resolves in skill content and **not** in a
`context/*.md` spoke, which is read raw:

```bash
journal_root="${CLAUDE_PLUGIN_DATA}/plugins-sync/runs"
```

See [context/sync.md](context/sync.md)'s "Run journal" section for what goes in it.

After Step 4 installs anything, reorder user-scope `enabledPlugins` with the bundled writer.
Never hand-edit `~/.claude/settings.json`:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/normalize-enabled-plugins.sh
```

That write is user-scope only. A project-scope map is inspected with `--report-project` and never
rewritten. See [context/sync.md](context/sync.md).

Read [context/scope-semantics.md](context/scope-semantics.md) before interpreting its output. In
particular the `versionsMatch` filter rule, never count or present a raw `divergences[]` length, is defined once there, under "Divergence is not automatically actionable"; every other mention in
this skill points at it rather than restating it.

## Action: audit

Read-only dry run of what `sync` (and, where relevant, `converge`) would do. Run the full algorithm
in [context/sync.md](context/sync.md) with every mutating CLI call replaced by "would run: `<command>`"
in the report. Call `fleet-state.sh`, compute the same install/enable/divergence deltas, but issue
**zero** `plugin install|update|uninstall|marketplace update` invocations. Predict `converge`'s
per-plugin intent (context/converge.md's preview step) the same way, without executing it. State-file
contents (`installed_plugins.json`, `known_marketplaces.json`, committed settings) are unchanged by
an `audit` run, modulo any concurrent session or background `autoUpdate` sweep. Note that caveat in
the report rather than asserting byte-identical files.

`audit` runs the same steps, which project their id lists with `--from` against a saved report, so
it does write those reports — to a throwaway `mktemp -d` scratch directory it deletes when the run
ends, never to the durable run journal under this plugin's data directory. That keeps one algorithm
for both actions while leaving nothing behind, which is what "mutates nothing" means here. See
[context/sync.md](context/sync.md)'s "Run journal" section.

Because `audit` issues no `marketplace update`, its Step 3 prediction is computed against an
**unrefreshed** catalog and is therefore a lower bound on what `sync` would update. Report it as one,
carrying the catalog's `lastUpdated`. See [context/sync.md](context/sync.md) Step 3. An `audit`
that predicts zero updates has not established that the fleet is current.

## Report

Terse, fixed sections. Detail only where action is required. Do not enumerate rows that need no
action.

```text
Marketplace: <name> — <current | needs update> (autoUpdate: <on|off — suggest enabling if off>)
  (repeat this line per marketplace in `all` mode — Steps 2–5 run once per marketplace)
In-repo: <N> project/local install(s) updated in <project_root>
  | 0 — <project_root> has no project/local installs
  | skipped — no project context resolved from <cwd>
Updated: <N> plugin(s) — <id>@<marketplace>: <old> → <new> (only when N > 0)
Installed: <N> new catalog plugin(s) — <id>@<marketplace> (only when N > 0; per install_new policy)
  (when the policy is `all`, append: policy install_new: all — these reinstall on every sync
   unless you also disable them)
Normalized: user enabledPlugins key order (<N> keys reordered)
  (only when Step 4 installed anything AND the user-scope map was rewritten; omit otherwise)
Divergences: <N> actionable (<M> newly created by this run — <a> by the in-repo update, <b> by the
  user-scope sweep, <N-M> pre-existing) → run `/claude-ops:plugins converge`
  (N = actionable only — versionsMatch:false; same-version multi-scope installs are not counted
  or listed here)
Stale project records: <K> record(s) across <P> path(s) not present on this machine
  (omit section entirely when K = 0; never counted in Divergences — see below for the row shape)
Cache content: <N> install(s) whose cache files disagree with their recorded gitCommitSha
  (omit the row entirely when N = 0; list the ids and the remediation — see below)
Action needed: <bulleted list — missing_from_user_install, missing_from_enabled, project-scope
  enable gaps, CLI failures, unknown/orphaned plugins, user_scope_orphans, plugin(s) installed this
  run with unset userConfig options, user-scope enabledPlugins reorder failures, a project-scope
  enabledPlugins map that is unsorted> (omit section entirely when empty)
```

**The `In-repo:` row is fixed. It appears whether or not the step did anything.** Step 2 calls
itself the primary value path, so a run in which it did nothing has to say so in the default output,
not only when it succeeds. The three variants are not cosmetic: `skipped` and `0` answer genuinely
different questions ("there was no *here* to update" versus "here has nothing installed"), and
collapsing them is the whole defect this row exists to close. `fleet-state.sh`'s top-level
`project_root` is what distinguishes them. See [context/sync.md](context/sync.md) Step 2.

Add a self-update row when Step 3's sweep updated `claude-ops` itself:

```text
Note: this run updated claude-ops (<old> → <new>). The algorithm that ran is the pre-update one —
  ${CLAUDE_PLUGIN_ROOT} still resolves to the version loaded at session start. /reload-plugins
  before relying on the new version.
```

(A plugin updated mid-session keeps resolving to the previous version's path. `plugins-reference`,
re-fetched 2026-09-05 and unchanged; behaviour observed on Claude Code 2.1.240 and not re-run on
2.1.261, because it needs an interactive session. See
[context/gotchas.md](context/gotchas.md).)

## Stale project records. Reported, never converged, never reaped

A project/local install record keeps its `projectPath` after that directory is gone. Ephemeral
checkouts make this ordinary rather than exceptional: a throwaway worktree can leave a record per
installed plugin behind, so one deleted directory can strand dozens of records at once.

`fleet-state.sh` annotates every project/local record with `projectPathPresent` (see
[context/scope-semantics.md](context/scope-semantics.md)). Report these in their **own section**, and
observe three boundaries:

- **Never counted in Divergences.** `converge`'s every project/local command is
  `(cd "<projectPath>" && claude plugin …)`, because `-s project`/`-s local` have no path flag. A row
  whose `projectPath` is absent cannot be `cd`'d into, so routing it to `converge` hands the user a
  command guaranteed to fail. Folding these into the actionable count also inflates it with rows no
  action can clear. They are a separate observation, not a divergence.
- **Never suppressed, and never called dead.** `projectPathPresent: false` means *not present on this
  machine right now*. Nothing more. An unmounted volume, an offline network share, an external drive
  that is unplugged, and a deleted worktree are indistinguishable to a directory test. Filtering these
  rows out would hide real drift from anyone whose repos live on removable or network storage. Say
  "not present on this machine", never "dead" or "orphaned".
- **Never reaped by this skill.** No `claude plugin` verb removes an install record by path;
  `prune` acts on auto-installed *dependencies* and its own `-s project` has the same
  no-path-flag limitation (re-verified on Claude Code 2.1.261). Editing `installed_plugins.json`
  directly is outside this skill's boundary, the same rule the rest of this skill follows. So this
  section names the condition and stops. If the records came from a tool that owns those directories'
  lifecycle, that tool is where they should be dropped at teardown; this skill does not reach into
  another plugin's configuration to find out.

A record does not have to come from a deliberate install. A repo whose committed `.claude/settings.json`
carries an `enabledPlugins` block mirroring what the user already has at user scope is a source of
these rows, because a project-scope entry takes precedence over user scope and so gets its own
version-pinned record keyed by that absolute path, one per plugin per checkout. Nothing on the other
side reaps the result either: `git worktree remove` does not touch `~/.claude`, and the product's
documented retention sweep covers nothing under `~/.claude/plugins/`.
[context/scope-semantics.md](context/scope-semantics.md) "Where project-scope records come from, and
why the skill cannot reap them" holds the sourcing, including the two questions still open.

Give the section a count plus the distinct paths, not one row per record, a hundred records naming
a dozen directories is a report about a dozen directories:

```text
Stale project records: <K> record(s) across <P> path(s) not present on this machine
  - <projectPath> — <n> record(s)
  (not counted as divergences: converge cannot cd into a path that is not present. A path can also
   be absent because a volume is unmounted or a share is offline — this is an observation, not a
   verdict that the directory is gone for good.)
```

A project-scope enable gap is a row `sync` deliberately does not fix. Step 5 enables automatically
only where the write is not team-shared state. Give each one its runnable command rather than a
count, so acting on it is a copy, not a reconstruction:

```text
- project-scope enable gap: (cd "<projectPath>" && claude plugin enable <id>@<marketplace> -s project)
  — writes that repo's committed .claude/settings.json; review the diff before committing
```

Only ids that Step 5 did not enable at `user`/`local` scope in this run appear here. For the rest
the command would fail rather than run, and Step 5 explains why.

When running inside a project (`CLAUDE_PROJECT_DIR` set and `fleet-state.sh`'s `installed[]` entries
carry `currentProject: true`), lead the Divergences line with *this* project's actionable count and
fold the rest of the machine into one trailing clause, e.g. `2 behind here → converge; 27 more
elsewhere on this machine`. Per-row detail (naming exact `<old> → <new>` versions per repo) is
reserved for genuine conflicts: an unknown/orphaned plugin id, or a CLI call that failed, never for
the routine bulk case. (Enable-state mismatches, a plugin `true` in one scope's `enabledPlugins`
and `false` in another, are a known blind spot, not a reportable category: `fleet-state.sh` only
exposes the merged effective value, never each scope's raw map, so this skill cannot detect one to
report it. See [context/converge.md](context/converge.md) "V1 scope".)

Close with reload guidance, stated as the docs' own two-step rather than as a prediction about which
case will trigger it: **recommend bare `/reload-plugins`; if it warns that the reload would
re-read the conversation, rerun it as `/reload-plugins --force`.** The general condition `--force`
exists for is prompt-cache invalidation, a plugin shipping an MCP server whose tools aren't deferred
is the common cause, not the only one, so do not present it as the sole trigger and do not tell the
user `--force` would be wrong when the bare command has already warned them. Never recommend
`--force` pre-emptively alongside every reload: it opts into a real token cost the bare command
declines to pay on its own (Claude Code ≥ 2.1.163; see
[context/scope-semantics.md](context/scope-semantics.md)). If any updated component includes a
monitor, call that out separately. Monitors need a full session restart, `/reload-plugins` doesn't
cover them.

## Cache content. Reported, never repaired

A version-and-sha check is not proof that the files on disk are the build the record names. When a
plugin's manifest version does not change across a commit, `claude plugin update` re-points the
record's `gitCommitSha` and leaves the existing version directory in place, so the metadata claims
the new commit while the directory still holds the old build. See
[context/scope-semantics.md](context/scope-semantics.md) for the observation this rests on.

Step 5b runs `cache-content-check.sh`, which byte-compares every file in each cache directory
against the recorded commit in the marketplace clone. Omit the `Cache content:` row when it finds
nothing. When it finds something, name the ids and give the remediation that was actually proved to
work, rather than a suggestion:

```text
Cache content: <N> install(s) whose cache files disagree with their recorded gitCommitSha
  - <id>@<marketplace> <version> — <n> file(s) differ
  Remediation: remove that version's directory under the plugin cache, then re-run
  `claude plugin update <id>@<marketplace>`, which recreates it from the clone.
```

**The check never repairs.** It does not delete a cache directory, does not re-run an update, and
does not `git fetch` a commit the marketplace clone lacks. A commit that is not local is reported as
`sha-not-local` and left alone: fetching is a network mutation this audit does not perform, and it
would also silently erase the condition the verdict exists to report. Every verdict other than
`match` and `stale-content` is counted as `unverifiable` — the audit looked and could not decide,
which is its own number and never folded into either side.

**Expect a substantial `unverifiable` share, and never read it as a pass.** Claude Code clones a
marketplace shallow, so any install whose recorded commit predates that clone's window reports
`sha-not-local` through no fault of the fleet. On the machine this check was first run against, 11
of 74 user-scope installs were unverifiable for exactly that reason. When the unverifiable count is
material, say so alongside the match count rather than leading with the match count alone.

## userConfig: `install_new`

Controls new-catalog-plugin install policy during `sync`. Ships as a plain `string` (the manifest
schema has no `enum` type. Verified against the published schema), default `"ask"`:

- `ask` (default). Offer every not-yet-installed catalog plugin in one batched multi-select prompt
- `all`. Install every not-yet-installed catalog plugin automatically
- `none`. Report them in "Action needed" only, never install

Any explicitly-set value other than these three is invalid; treat it as `ask` and note the invalid
value in the report.

**Configured value: `${user_config.install_new}`**. Claude Code text-substitutes a `userConfig`
value into this skill's content before the model sees the rendered skill, but **only when the key is
explicitly set** in user settings (`~/.claude/settings.json`), `--settings`, or managed settings: precedence managed → `--settings` → user. It is **not** "some `pluginConfigs` scope": a project's
`.claude/settings.json` or `.claude/settings.local.json` entry is ignored, and setting `install_new`
there does nothing at all. Declaring the option in `plugin.json` alone does not make its value
readable here either. See [context/scope-semantics.md](context/scope-semantics.md) for the read path
and why it differs from `enabledPlugins`, which this same skill reads from project and local scope.

Crucially, the manifest's `"default": "ask"` is **not** substituted for
an unset key (verified 2026-07-23 against CC 2.1.218: an unset key leaves the placeholder token
unchanged, the same shape as `${user_config.…}`, while a sibling `${CLAUDE_PLUGIN_ROOT}` substitutes
in the same render). **Recheck trigger:** re-verify on any Claude Code minor-version bump that
touches plugin `userConfig` substitution, or once `plugins-reference` gains text on unset-key
rendering, the docs are silent on it today, so this claim rests entirely on that one probe, and the
probe's CLI version has since moved (2.1.218 → 2.1.261) with the claim unre-tested.

A 2026-09-05 attempt to re-run it on 2.1.261 was **inconclusive, not a confirmation**, and the
reason is worth carrying: a throwaway plugin was loaded from a local marketplace with one
`userConfig` key left unset and a sibling key set through `--settings` `pluginConfigs` under the
plugin's fully-qualified id. In the rendered skill body `${CLAUDE_PLUGIN_ROOT}` substituted, so the
render pass certainly ran, but **both** `userConfig` tokens came through literal, including the one
that was explicitly set. With the positive control failing there is no way to tell an unset key
leaving its placeholder apart from `userConfig` substitution not reaching skill content on that
path at all. The remaining discriminator, setting the key in `~/.claude/settings.json`, was out of
bounds for a probe that must not mutate real machine state. Treat the claim as still resting on the
2.1.218 probe, and treat the failed control as its own open question rather than as evidence for
the claim. So for the common default-config user — no `pluginConfigs` set anywhere — the
**Configured value** line above still shows that literal placeholder token, not `ask`.

Read that literal placeholder token as the **expected unset state → use the default `ask`**, and do NOT
report it as an invalid value. Only a rendered value that is a real word other than
`ask`/`all`/`none` (i.e. the key *was* set, to something unsupported) is the invalid-value case worth
flagging. Sync's Step 4 branches on the **Configured value** line's rendered value, or on the `ask`
default when that render is still the placeholder token, not on the option's name or description above.

## Reference index. Load on demand

| File | Load when |
|---|---|
| [context/sync.md](context/sync.md) | Running `sync` or `audit`; it is the step sequence both actions execute. |
| [context/sync-install-enable.md](context/sync-install-enable.md) | Sync Steps 4 and 5, and only when the fresh pre-Step-4 re-read (not Step 1's report) has a non-empty `missing_from_user_install` or `missing_from_enabled`, or its Step 1 refresh failed. Both arrays are empty on a current fleet. |
| [context/converge.md](context/converge.md) | Running `converge`, the only action that may rewrite a committed settings file. |
| [context/scope-semantics.md](context/scope-semantics.md) | A scope, version, or reload claim needs its verified source before you act on it. |
| [context/gotchas.md](context/gotchas.md) | A run failed in a way the steps do not explain, or a safeguard looks removable. |
