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

## Version capture for the report

SKILL.md's report requires `<id>@<marketplace>: <old> → <new>` for every updated plugin, so both
values have to be collected while the sweep runs — neither can be reconstructed afterward. Three
sources, in precedence order, and **never** a synthesized value:

1. **`<old>`** — that id's `installed[].version` from the pre-mutation `fleet-state.sh` re-read the
   section above already requires. It is the pre-update value by construction.
2. **`<new>`** — the `claude plugin update` call's own output for that id when it names a version.
   Capture the CLI's line as it runs; it is the only source that reflects the update immediately.
3. **`<new>` fallback** — that id's `installed[].version` from one `fleet-state.sh` re-read after
   the Step 2 + Step 3 sweep completes, diffed against the pre-sweep snapshot.

Source 3 is a fallback rather than the primary because `claude plugin update`'s own help says
"restart required to apply", and this skill has not established when the CLI writes
`installed_plugins.json` relative to that restart. If the write is deferred, the post-sweep re-read
shows the pre-update version for a plugin that did update. So: when the CLI reported an update for
an id and the post-sweep version is unchanged, report the CLI's reported value, or `<unknown>` if it
named none — never report `<old> → <old>`, and never count that id as not-updated. A report line
that says nothing changed for a plugin that did change is worse than one that admits it cannot tell.

One data point, not a licence to drop the fallback: on Claude Code 2.1.228 a 63-plugin user-scope
sweep had all 21 CLI-reported updates already reflected in a post-sweep `fleet-state.sh` re-read, so
source 3 agreed with source 2 on every id. That establishes the write landed before the re-read on
that run — not that it is synchronous per call, and not that it holds on another version. Keep
source 2 primary and keep the divergence handling above.

## Step 1 — Marketplace refresh

For each target marketplace (the resolved default, the named one, or every marketplace when the
argument is `all`):

```bash
claude plugin marketplace update <marketplace-name>
```

Attempts to re-fetch from the marketplace's registered source (per Brief Decision 4 — no manual
re-clone or cache surgery). It does not reliably self-heal: the refresh is known to fail against an
existing non-empty marketplace directory
([anthropics/claude-code#76129](https://github.com/anthropics/claude-code/issues/76129), open —
reported on macOS, reproduced on Windows), where it reports `Failed to clone marketplace
repository: fatal: destination path '...' already exists and is not an empty directory`. Treat a
successful refresh as the expected case, not a guarantee.

In `all` mode, loop this per marketplace name (rather than the bulk no-argument form) so a single
marketplace's failure is attributable and reported inline without aborting the sweep for the rest.

**On a non-zero exit — every mode, including single/default.** Not fatal, and never silently
absorbed: report the marketplace and the CLI's own error text inline under "Action needed" and
continue to Step 2. Steps 2–3 operate on installed state, which a failed marketplace refresh
leaves untouched. Steps 4–5 do NOT: Step 4 derives installations from the catalog
(`missing_from_user_install`) and Step 5 consults catalog metadata (`defaultEnabled`), so running
them against a stale catalog can install a since-removed plugin or enable one the publisher has
since made opt-in-only. For a marketplace whose refresh failed, **skip Steps 4–5** and list what
they would have done under "Action needed" as deferred until a sync run where the refresh
succeeds. Say so in the report (`Marketplace: <name> — refresh failed, catalog may be stale;
install/enable maintenance deferred`) rather than claiming it is current. Do not delete, rename,
or re-clone the marketplace directory to work around it — that is cache surgery this skill does
not do. To learn how stale the catalog actually is, compare `git -C <installLocation> rev-parse
HEAD` against `git ls-remote origin HEAD` run in that directory — `ls-remote` queries the remote
without writing `FETCH_HEAD`, remote-tracking refs, or objects, all three of which a plain
`git fetch` writes (mutations of the marketplace's internal clone, outside this skill's boundary).

## Step 2 — In-repo update (the primary value path)

Always call `fleet-state.sh` first — never gate this step on `CLAUDE_PROJECT_DIR` being set before
calling it. `fleet-state.sh` resolves the project root itself (`CLAUDE_PROJECT_DIR` when set, else
the cwd's git toplevel, else a non-git cwd corroborated by its own `.claude` directory — `$HOME`
excluded; see [gotchas.md](gotchas.md)), so a headless session where the env var is unset can still
correctly compute `currentProject`; gating on the raw env var directly would skip this step in
exactly the case that fallback exists for.

Look at `installed[]` entries with `currentProject: true` and run an update for **every one of
them**, unconditionally:

```bash
claude plugin update <id> -s project   # for a currentProject:true entry with scope "project"
claude plugin update <id> -s local     # for a currentProject:true entry with scope "local"
```

`fleet-state.sh --ids current-project` emits exactly those ids, one per line — use it rather than a
hand-written `jq` over `installed[]` (see Step 3 for why the hand-written form breaks on Windows).
The per-entry `scope` still comes from the JSON, since it decides which `-s` flag each id takes.

Do **not** pre-filter on `divergences[]`. `divergences[]` only contains ids with *more than one*
scope record — a project/local install with no other scope pinning the same id (the common single-
pin case) never appears there at all, and neither does a multi-scope install where every scope
happens to already share the same stale version (`versionsMatch: true` — still behind the catalog,
just not internally disagreeing). Both are real staleness `fleet-state.sh` cannot detect from its own
output (it has no per-plugin catalog version to compare against), so the only correct signal is
"is this entry present" — mirror Step 3's own pattern and just call `update`, letting the CLI report
"already at the latest version" as a no-op when nothing changes. Verified safe: `plugin update
-s project` does not write the committed `.claude/settings.json` (see
[scope-semantics.md](scope-semantics.md)) — no settings-diff review needed for this step, unlike
`converge`.

## Step 3 — User-scope update sweep

For every catalog plugin id currently installed at `user` scope, run:

```bash
claude plugin update <id> -s user
```

One call per plugin — `claude plugin update` takes a single `<plugin>` argument, there is no bulk
"update everything" flag. Loop it; a single plugin's update failure is reported inline (under
"Action needed") and does not abort the sweep for the rest.

Take the ids from `fleet-state.sh --ids`, never from a hand-written `jq` over its JSON:

```bash
while IFS= read -r id; do
  [ -n "$id" ] || continue
  claude plugin update "$id" -s user
done < <("${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh --ids installed-user)
```

`--ids` emits the fully-qualified `<name>@<marketplace>` form, one per line, CR-free — a bare name
fails with "Plugin not found" even when unambiguous, and on Windows a hand-written
`jq -r ... | while read` silently appends a `\r` to every id but the last, which fails with the
*same* "Plugin not found" text and so misreads as the bare-name problem. Both are
[gotchas.md](gotchas.md); `--ids` is why neither can happen here.

## Step 4 — Install new catalog plugins (per `install_new` policy)

Catalog-dependent: skipped (deferred) for a marketplace whose Step 1 refresh failed — see Step 1.

Take `fleet-state.sh`'s `missing_from_user_install` (`--ids missing-user-install` emits the id list
directly — see Step 3) — catalog ids not installed at `user` scope
(already excludes anything explicitly opted out with `enabledPlugins: false` in any scope — never
re-offer a deliberate decline). This is deliberately user-scope, not the all-scope `missing_from_install`:
a plugin installed only at `project`/`local` scope is absent from `missing_from_install` yet still not
usable from other directories, so installing at `user` scope below (the "usable from any directory"
guarantee) must key off user-scope completeness. Apply the configured
policy — SKILL.md's `${user_config.install_new}` line renders the actual value; that render, not this
step's prose, is what to branch on:

- **`ask`** (default) — present every entry in one batched `AskUserQuestion` multi-select, then
  `claude plugin install <id> -s user` for each the user picks
- **`all`** — `claude plugin install <id> -s user` for every entry, no prompt
- **`none`** — install nothing; list the entries under "Action needed" in the report only

**Caveat (document, don't silently absorb):** with `install_new: all`, a catalog plugin that's
installed at `user` scope and then *disabled* (not uninstalled — `enabledPlugins: false` still
recorded, install record still present) is correctly excluded (it's not in `missing_from_user_install`,
it's an installed, opted-out plugin). But a plugin that's *uninstalled entirely* without ever setting
`false` reappears in `missing_from_user_install` on the very next sync and gets reinstalled —
`install_new: all` has no memory of "I removed this on purpose." If that's not the intent, uninstall
AND disable (`enabledPlugins: false`), or switch the policy to `ask`/`none`.

## Step 5 — `enabledPlugins` completeness

Catalog-dependent (`defaultEnabled` comes from catalog metadata): skipped (deferred) for a
marketplace whose Step 1 refresh failed — see Step 1.

Take `fleet-state.sh`'s `missing_from_enabled` (`--ids missing-enabled` emits the id list directly —
see Step 3) — ids installed somewhere but never mentioned (true
or false) in any scope's `enabledPlugins`, already excluding ids the marketplace ships with
`defaultEnabled: false`. That field is a publisher's deliberate opt-in-required default (it takes
precedence over the plugin's own `plugin.json` field — see
[scope-semantics.md](scope-semantics.md)); no explicit `enabledPlugins` entry for one of those ids is
the *intended* state, not a completeness gap — never run `enable` for it. This only catches the
default recorded in the marketplace entry; a plugin whose `defaultEnabled: false` lives only in its
own `plugin.json`, with no mirrored marketplace-entry override, is a known residual gap (`fleet-state.sh`
reads the marketplace's catalog file, never each installed plugin's own manifest).

Consider each remaining id in each *verifiable* scope where it has an install record (from
`installed[]`) but no raw entry in that scope's own `enabledPlugins` map — **`user` scope, or
`project`/`local` scope with `currentProject: true`, never a `project`/`local` record for a different
repo** (same restriction as `missing_from_enabled` itself, for the same reason: this invocation never
reads another repo's settings files, so it cannot know whether that record is genuinely unmentioned
there or already has its own entry — acting on it would risk mutating the current repo or an unread
repo instead).

**`sync` never writes a committed settings file — the scope decides whether this step acts or
reports.** SKILL.md's scope section makes `converge` the one action that may touch a committed
`.claude/settings.json`, and only behind its confirm gate. `enable <id> -s project` writes exactly
that file (verified on Claude Code 2.1.228 — see [scope-semantics.md](scope-semantics.md)), so this
step must not issue it. Confirming instead of skipping is not an option: `converge` can afford a
confirm because it *aborts* in an autonomous session, while `sync` is the on-demand and headless
maintenance action with no such abort, so there may be no human to answer.

- **`user` and `local` — enable automatically.** Neither is team-shared state: `user` writes
  machine-scope `~/.claude/settings.json`, and `local` writes the gitignored
  `.claude/settings.local.json`.

  ```bash
  claude plugin enable <id> -s user     # or -s local
  ```

- **`project` — never enable; report it, but only when the report would be runnable.** Emit an
  "Action needed" row per SKILL.md's Report section carrying the exact command, so the user can run
  it deliberately and review the resulting diff:

  ```bash
  (cd "<that record's projectPath>" && claude plugin enable <id>@<marketplace> -s project)
  ```

  The `cd`-into-its-own-`projectPath` form is required for the reason
  [converge.md](converge.md) Step 2 gives — `-s project` has no path flag and always acts on the
  current directory — and the id stays fully qualified per [gotchas.md](gotchas.md).

  **Order matters — suppress this row for any id the `user`/`local` branch just enabled.** An id
  with no `enabledPlugins` entry anywhere but install records at *both* `user` and `project` scope
  produces two rows in one run. The `user` row enables first, and `enable -s project` gates on the
  **merged effective** value, not that scope's raw map (see
  [scope-semantics.md](scope-semantics.md)), so the reported command would then fail with
  `Plugin "<id>" is already enabled at project scope` — a report that hands the user a command
  guaranteed to error. Emit the `project` row only for an id this step did **not** enable at `user`
  or `local` scope; in practice that means an id whose only verifiable record is the project one.
  Skipping is correct rather than merely convenient: after the `user` enable the plugin already
  loads in that project by scope precedence, so nothing is broken — only the team-shared *declaration*
  is absent, and that is a deliberate choice for the user to make, not drift for `sync` to report as
  actionable.

Never touches an id that has an explicit entry anywhere (true — already enabled, nothing to do; or
false — deliberate opt-out, never flipped). This step only fills a genuine gap: installed but never
recorded either way.

## Step 6 — Report

Emit the report per SKILL.md's "Report" section, filling each updated plugin's `<old> → <new>` from
the sources the "Version capture for the report" section above fixes. End with reload guidance: bare `/reload-plugins` by
default; suggest `--force` only when an updated/installed component ships an MCP server whose tools
aren't deferred (see [scope-semantics.md](scope-semantics.md) — `--force` exists to opt into a real
token cost, not a blanket recommendation). Call out a session restart separately only when an updated
component ships a monitor (monitors aren't covered by `/reload-plugins`).
