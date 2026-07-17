# Sync algorithm

`sync` is the default action: bring the effective fleet current where you stand. Every step below
is CLI-mediated — never edit `installed_plugins.json`, `known_marketplaces.json`, or any
`.claude/settings*.json` directly. `audit` runs this same sequence with every mutating call replaced
by a prediction (see SKILL.md's "Action: audit").

## Concurrency

The `claude plugin` CLI is the serialization point — there is no separate lock this skill manages.
Re-read state (re-run `fleet-state.sh`) immediately before each mutating step rather than mutating
off a snapshot taken several steps ago; a background `autoUpdate` sweep or a concurrent session can
change installed/enabled state between steps. Note in the report when a mutation's outcome doesn't
match what the pre-mutation snapshot predicted — that's this race, not a bug.

## Step 1 — Marketplace refresh

For each target marketplace (the resolved default, the named one, or every marketplace when the
argument is `all`):

```bash
claude plugin marketplace update <marketplace-name>
```

Self-heals a stale or corrupt local clone by re-fetching from the marketplace's registered source
(per Brief Decision 4 — no manual re-clone or cache surgery). In `all` mode, loop this per
marketplace name (rather than the bulk no-argument form) so a single marketplace's failure is
attributable and reported inline without aborting the sweep for the rest.

## Step 2 — In-repo update (the primary value path)

Only when `CLAUDE_PROJECT_DIR` is set (you're standing inside a project). Call `fleet-state.sh` and
look at `installed[]` entries with `currentProject: true`:

```bash
claude plugin update <id> -s project   # for a currentProject:true entry with scope "project"
claude plugin update <id> -s local     # for a currentProject:true entry with scope "local"
```

Run this **only** for entries whose id also appears in `divergences[]` with `versionsMatch: false` —
a `currentProject: true` entry with no divergence is already current, nothing to do. Verified safe:
`plugin update -s project` does not write the committed `.claude/settings.json` (see
[scope-semantics.md](scope-semantics.md)) — no settings-diff review needed for this step, unlike
`converge`.

## Step 3 — User-scope update sweep

For every catalog plugin id currently installed at `user` scope (from `fleet-state.sh`'s
`installed[]`, `scope == "user"`), run:

```bash
claude plugin update <id> -s user
```

`<id>` here is always the fully-qualified `<name>@<marketplace>` form `fleet-state.sh` already
emits — a bare name fails with "Plugin not found" even when unambiguous (see
[gotchas.md](gotchas.md)).

One call per plugin — `claude plugin update` takes a single `<plugin>` argument, there is no bulk
"update everything" flag. Loop it; a single plugin's update failure is reported inline (under
"Action needed") and does not abort the sweep for the rest.

## Step 4 — Install new catalog plugins (per `install_new` policy)

Take `fleet-state.sh`'s `missing_from_install` (already excludes anything explicitly opted out with
`enabledPlugins: false` in any scope — never re-offer a deliberate decline). Apply the
`install_new` userConfig value:

- **`ask`** (default) — present every entry in one batched `AskUserQuestion` multi-select, then
  `claude plugin install <id> -s user` for each the user picks
- **`all`** — `claude plugin install <id> -s user` for every entry, no prompt
- **`none`** — install nothing; list the entries under "Action needed" in the report only

**Caveat (document, don't silently absorb):** with `install_new: all`, a catalog plugin that's
installed and then *disabled* (not uninstalled — `enabledPlugins: false` still recorded, install
record still present) is correctly excluded (it's not in `missing_from_install`, it's an installed,
opted-out plugin). But a plugin that's *uninstalled entirely* without ever setting `false` reappears
in `missing_from_install` on the very next sync and gets reinstalled — `install_new: all` has no
memory of "I removed this on purpose." If that's not the intent, uninstall AND disable
(`enabledPlugins: false`), or switch the policy to `ask`/`none`.

## Step 5 — `enabledPlugins` completeness

Take `fleet-state.sh`'s `missing_from_enabled` — ids installed somewhere but never mentioned (true
or false) in any scope's `enabledPlugins`. For each, and for each scope where that id has an install
record (from `installed[]`) but no raw entry in that scope's own `enabledPlugins` map:

```bash
claude plugin enable <id> -s <that scope>
```

Never touches an id that has an explicit entry anywhere (true — already enabled, nothing to do; or
false — deliberate opt-out, never flipped). This step only fills a genuine gap: installed but never
recorded either way.

## Step 6 — Report

Emit the report per SKILL.md's "Report" section. End with reload guidance: bare `/reload-plugins`
(verified — no `--force` flag exists); call out a session restart separately only when an updated
component ships a monitor (monitors aren't covered by `/reload-plugins`).
