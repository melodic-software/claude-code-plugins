# Sync algorithm

`sync` is the default action: bring the effective fleet current where you stand. Every step below
is CLI-mediated — never edit `installed_plugins.json`, `known_marketplaces.json`, or any
`.claude/settings*.json` directly. `audit` runs this same sequence with every mutating call replaced
by a prediction (see SKILL.md's "Action: audit").

## Concurrency

The `claude plugin` CLI is the serialization point — there is no separate lock this skill manages.

**The re-read boundary is the STEP, not the individual mutation.** Re-run `fleet-state.sh`
immediately before each mutating step rather than mutating off a snapshot taken several steps ago; a
background `autoUpdate` sweep or a concurrent session can change installed/enabled state between
steps. Inside a step, the loop body is deliberately snapshot-driven: Step 3 reads its id list once
and then issues one `claude plugin update` per line. That is the intended design, not a violation of
the rule above. Re-reading state before each of sixty-odd calls would buy nothing — the CLI is the
serialization point, so the worst outcome of losing the race on any single id is that the id was
already updated by whoever won it, and the call degrades to a no-op.

Detecting that race is not something this step can do from CLI output, so do not pretend to. An
id reported "already at the latest version" is *equally* consistent with a benign no-op and with a
concurrent sweep having just updated it; the two are indistinguishable, and a report row that claims
to tell them apart would be inventing a signal. The one outcome that **is** distinguishable, and
worth a report row under "Action needed", is an id present in the pre-mutation snapshot that the CLI
then reports as **not installed** — that is a genuine concurrent uninstall, not this benign race.

## Version capture for the report

SKILL.md's report requires `<id>@<marketplace>: <old> → <new>` for every updated plugin, so both
values have to be collected while the sweep runs — neither can be reconstructed afterward.

**Retain the pre-sweep `fleet-state.sh` output for the whole run.** It is the sole source of every
`<old>`, and once Step 2/3 have run there is nothing left on the machine that still holds those
values — the pre-update versions are gone. Keep that snapshot (and each `claude plugin update` line
as it is emitted) available through Step 6 rather than assuming it can be recovered; a sweep of
several dozen mutations whose report depends on the `<old> → <new>` pairs is otherwise one context
compaction away from being unable to emit its own report. This skill provides no durable log for
that today — see "Deferred" in the plugin's CHANGELOG for why the script does not write one.

Three sources, in precedence order, and **never** a synthesized value:

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

## Marketplace scoping — Steps 2–5 are the per-marketplace loop body

**Every `fleet-state.sh` call in Steps 2–5 carries `--marketplace "$mp"`, and in `all` mode the whole
of Steps 2–5 is the loop body, run once per marketplace.** Without this, `all` mode refreshes every
marketplace in Step 1 and then performs install, update, enable, and divergence maintenance against
exactly **one** of them — the resolved default — while emitting a report that names no coverage
boundary. That is a silent partial sweep: the plugins of every other marketplace are neither updated
nor reported as skipped.

Get the names from `fleet-state.sh --marketplaces`, never from a hand-written `jq` over
`known_marketplaces.json` — enumerating names has exactly the trailing-`\r` hazard that enumerating
ids does, and for the same reason:

```bash
while IFS= read -r mp; do
  [[ -n "$mp" ]] || continue
  # Steps 2–5 for "$mp"
done < <("${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh --marketplaces)
```

The bare (no `--marketplace`) form is not a fleet-wide form; it resolves the default marketplace and
scopes to it. Nor can the sweep be widened by combining flags — the script refuses that composition
outright and names the fix in its own error text:

```text
$ fleet-state.sh --all --ids installed-user
ERROR: --ids cannot be combined with --all
  Run --ids once per marketplace with --marketplace <name>.
```

(Verified on Claude Code 2.1.240.) `--all` exists for the JSON report, which nests one block per
marketplace; `--ids` projects a single block, so it takes one marketplace at a time. Loop it.

The per-marketplace failure rule from Step 1 carries through: a marketplace whose iteration fails is
reported inline and never aborts the loop for the rest.

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
continue to Step 2.

Which later steps a stale catalog compromises, and how each one degrades:

- **Step 2 is unaffected.** It operates purely on installed state, which a failed refresh leaves
  untouched, and it is deliberately not catalog-pre-filtered (see Step 2).
- **Step 3 still runs, but WITHOUT its pre-filter.** Its sweep is installed-state-driven, so the
  updates themselves are safe — but the `catalog_versions` pre-filter reads the marketplace
  *checkout*, and a checkout that failed to refresh may be behind the real catalog. An id whose
  installed version matches the **stale** catalog version would then be withheld from the sweep as
  "already current" when a newer version exists upstream — a silently skipped update, which is
  exactly the class of failure this skill exists to prevent. So for a marketplace whose Step 1
  refresh failed, Step 3 falls back to `--ids installed-user` and sweeps every user-scope id
  unconditionally. Correctness over speed: the pre-filter is an optimization, and an optimization
  keyed on data known to be stale is not one.
- **Steps 4–5 are skipped entirely.** Step 4 derives installations from the catalog
  (`missing_from_user_install`) and Step 5 consults catalog metadata (`defaultEnabled`), so running
  them against a stale catalog can install a since-removed plugin or enable one the publisher has
  since made opt-in-only. For a marketplace whose refresh failed, **skip Steps 4–5** and list what
  they would have done under "Action needed" as deferred until a sync run where the refresh
  succeeds.

Say so in the report — `Marketplace: <name> — refresh failed, catalog may be stale; update sweep
ran unfiltered; install/enable maintenance deferred` — rather than claiming it is current. Do not
delete, rename, or re-clone the marketplace directory to work around it — that is cache surgery
this skill does not do. To learn how stale the catalog actually is, compare
`git -C <installLocation> rev-parse HEAD` against `git ls-remote origin HEAD` run in that
directory — `ls-remote` queries the remote
without writing `FETCH_HEAD`, remote-tracking refs, or objects, all three of which a plain
`git fetch` writes (mutations of the marketplace's internal clone, outside this skill's boundary).

## Step 2 — In-repo update (the primary value path)

Always call `fleet-state.sh` first — never gate this step on `CLAUDE_PROJECT_DIR` being set before
calling it. `fleet-state.sh` resolves the project root itself (`CLAUDE_PROJECT_DIR` when set, else
the cwd's git toplevel, else a non-git cwd corroborated by its own `.claude` directory — `$HOME`
excluded; see [gotchas.md](gotchas.md)), so a headless session where the env var is unset can still
correctly compute `currentProject`; gating on the raw env var directly would skip this step in
exactly the case that fallback exists for.

**Before looping, branch on the report's top-level `project_root` — this step must never skip
silently.** It is the primary value path; a run where it did nothing has to say so, and until it
does, "no project context at all" and "a project with no in-repo installs" produce an identical
report. They are categorically different answers and the user cannot tell them apart:

- **`project_root` is `null`** — no project root resolved (a run from `$HOME`, or from a non-git
  directory with no `.claude` of its own). Nothing in-repo can be updated because there is no
  "here". Emit the skipped `In-repo:` row from SKILL.md's Report section, naming the cwd, and go to
  Step 3. Do **not** report this as "0 updated".
- **`project_root` is a path and no record carries `currentProject: true`** — a project resolved and
  it simply has no project/local-scope installs. Emit the `In-repo:` row as `0` **for that root**,
  which is an honest zero rather than an absent step.
- **`project_root` is a path and records carry `currentProject: true`** — the success path below.

Reading `project_root` costs nothing extra: this step already calls `fleet-state.sh` above, and the
field is in the JSON it returned. Do not try to recover the distinction from `--ids current-project`
alone — that selector emits nothing in both of the first two cases, which is exactly why the step
used to no-op invisibly. And do not infer it from `currentProject` per record either: that flag is a
tri-state whose `null` covers user-scope records, records with no `projectPath`, *and* the
no-project-context case all at once.

Then look at `installed[]` entries with `currentProject: true` and run an update for **every one of
them**, unconditionally:

```bash
claude plugin update <id> -s project   # for a currentProject:true entry with scope "project"
claude plugin update <id> -s local     # for a currentProject:true entry with scope "local"
```

`fleet-state.sh --ids current-project` emits exactly those records — use it rather than a
hand-written `jq` over `installed[]` (see Step 3 for why the hand-written form breaks on Windows).
Each line is `<id>\t<scope>`, so the `-s` flag comes off the same line as the id it belongs to:

```bash
while IFS=$'\t' read -r id scope; do
  [[ -n "$id" ]] || continue
  claude plugin update "$id" -s "$scope"
done < <("${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh --marketplace "$mp" --ids current-project)
```

The scope rides on the record for a reason: one plugin can hold **both** a `project`- and a
`local`-scope record for the same repo (the multi-scope case `divergences[]` tracks), and both are
`currentProject: true`. An id-only list would show that id twice with nothing to distinguish the
lines — `sort -u`, or pairing against a separately-extracted scope list, would silently drop one of
the two updates. Do not re-derive scope from the id afterwards.

Do **not** pre-filter on `divergences[]`. `divergences[]` only contains ids with *more than one*
scope record — a project/local install with no other scope pinning the same id (the common single-
pin case) never appears there at all, and neither does a multi-scope install where every scope
happens to already share the same stale version (`versionsMatch: true` — still behind the catalog,
just not internally disagreeing). Both are real staleness `divergences[]` cannot express, so the only
correct signal here is "is this entry present" — just call `update`, letting the CLI report
"already at the latest version" as a no-op when nothing changes.

Deliberately **not** pre-filtered on `catalog_versions` the way Step 3's sweep is, even though the
field is now available for these ids too. The in-repo population is small (a handful of records,
against Step 3's dozens), so the saving is negligible, while a project/local pin is far more likely
than a user-scope install to sit at a version the catalog does not carry — a deliberate pin, or a
local build. Paying one redundant no-op call per in-repo record buys the primary value path a
signal that does not depend on the catalog resolving at all. Verified safe: `plugin update
-s project` does not write the committed `.claude/settings.json` (see
[scope-semantics.md](scope-semantics.md)) — no settings-diff review needed for this step, unlike
`converge`.

## Step 3 — User-scope update sweep

Partially catalog-dependent: the sweep itself is installed-state-driven and always runs, but its
pre-filter reads the marketplace checkout. Two cases where that checkout cannot be trusted to prove
an id current, and what each does:

- **Step 1's refresh failed for this marketplace** — use `--ids installed-user` instead of
  `--ids update-candidates-user`, and sweep unconditionally. See Step 1.
- **`audit` mode** — `audit` issues zero mutating calls, so Step 1 never runs and the catalog is
  simply however stale it already was, by an unbounded amount. The pre-filter still runs (predicting
  the real algorithm is the point of a dry run), but its output is a **lower bound**: a real `sync`
  refreshes first and may find more to update. Say so, and quantify the uncertainty with the
  catalog's own age rather than leaving it implicit — `fleet-state.sh` reports
  `marketplace.lastUpdated`:

  ```text
  Would update: <N> plugin(s) (lower bound — predicted against a catalog last refreshed
    <lastUpdated>, which `audit` does not refresh; `sync` refreshes first and may find more)
  ```

  Never present an `audit` prediction of zero as "the fleet is current" — it means "nothing is
  behind the catalog as it stands on disk", which is a different claim.

Everything else in this step is unchanged.

Update the catalog plugins installed at `user` scope:

```bash
claude plugin update <id> -s user
```

One call per plugin — `claude plugin update` takes a single `<plugin>` argument, there is no bulk
"update everything" flag. Loop it; a single plugin's update failure is reported inline (under
"Action needed") and does not abort the sweep for the rest.

Take the ids from `fleet-state.sh --ids`, never from a hand-written `jq` over its JSON, and use the
**`update-candidates-user`** selector rather than `installed-user`:

```bash
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  claude plugin update "$id" -s user
done < <("${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh --marketplace "$mp" --ids update-candidates-user)
```

### Why the pre-filter, and why it can only ever be a candidate list

Each plugin's version lives in its own manifest inside the marketplace checkout
(`<installLocation>/<entry.source>/.claude-plugin/plugin.json`), even though the `marketplace.json`
entry itself carries no version. `fleet-state.sh` reads those manifests into `catalog_versions` with
no network call and no `claude plugin` invocation, and `update-candidates-user` withholds only the
ids it positively proved already sit at the catalog version. On an already-current fleet that turns
the whole sweep into zero `claude plugin update` calls instead of one per user-scope install.

It is not free, just far cheaper than what it replaces: the read costs one local file parse per
catalog entry (plus one path resolution per entry that actually resolves), against `claude plugin
update` process launches it removes. Local file reads, no network, no CLI.

**Correctness dominates the saving, so the selector fails open by construction.** An id whose
catalog version cannot be read — the entry's `source` is a remote spec rather than a repo-relative
path, the checkout never materialized that directory, the manifest carries no `version`, the JSON
does not parse — is emitted as a candidate, exactly as if no pre-filter existed. That is not a rare
branch: across the marketplaces registered on the authoring machine (Claude Code 2.1.240) the
version resolved for every entry of some and for a small minority of others', so a marketplace where
the pre-filter withholds nothing at all is an ordinary outcome, not a malfunction. Read a shrunken
sweep as a bonus, never as evidence that the ids it skipped were checked.

`installed-user` remains available and unchanged for a caller that deliberately wants every
user-scope id. Do not reach for it here to "be safe" when the catalog is trustworthy —
`update-candidates-user` is already a superset of what needs updating. Reach for it in the one case
where the catalog itself is suspect: **a marketplace whose Step 1 refresh failed.** The pre-filter's
guarantee is "this id matches the version in the local checkout"; that is only a statement about
staleness when the checkout is current.

`--ids` emits the fully-qualified `<name>@<marketplace>` form, one per line, CR-free — a bare name
fails with "Plugin not found" even when unambiguous, and on Windows a hand-written
`jq -r ... | while read` silently appends a `\r` to every id but the last, which fails with the
*same* "Plugin not found" text and so misreads as the bare-name problem. Both are
[gotchas.md](gotchas.md); `--ids` is why neither can happen here.

## Step 4 — Install new catalog plugins (per `install_new` policy)

Catalog-dependent: skipped (deferred) for a marketplace whose Step 1 refresh failed — see Step 1.

Take `fleet-state.sh`'s `missing_from_user_install` (`--marketplace "$mp" --ids missing-user-install`
emits the id list directly — see Step 3) — catalog ids not installed at `user` scope
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

**A headless run launched with `--setting-sources` that omits `user` silently reverts this policy to
`ask`.** `pluginConfigs` is read from user settings, `--settings`, and managed settings only (see
[scope-semantics.md](scope-semantics.md)), so dropping `user` from the source list drops the
configured `install_new` with it — and the render falls back to the unset placeholder, which this
step correctly reads as `ask`. That is the right fallback and the wrong silence: say so in the
report rather than letting a policy the user set appear to have been honored.

**Caveat (document, don't silently absorb):** with `install_new: all`, a catalog plugin that's
installed at `user` scope and then *disabled* (not uninstalled — `enabledPlugins: false` still
recorded, install record still present) is correctly excluded (it's not in `missing_from_user_install`,
it's an installed, opted-out plugin). But a plugin that's *uninstalled entirely* without ever setting
`false` reappears in `missing_from_user_install` on the very next sync and gets reinstalled —
`install_new: all` has no memory of "I removed this on purpose." If that's not the intent, uninstall
AND disable (`enabledPlugins: false`), or switch the policy to `ask`/`none`.

**Say that in the report, at the moment it fires.** When the policy is `all` and this step installed
anything, the `Installed:` row carries the recurrence clause from SKILL.md's Report section. A
caveat documented only here is invisible to the person reading the report, who is exactly the person
about to be surprised by it on the next run. Do not leave it to inference.

**Capture each install's own CLI output, don't discard it.** An install can report that the plugin
declares `userConfig` options left unset, along with its own suggested remedy. That line is
per-install information this step is the only one positioned to see, and it belongs in the report's
"Action needed" list rather than in the scrollback — see SKILL.md's Report section for the slot.

## Step 5 — `enabledPlugins` completeness

Catalog-dependent (`defaultEnabled` comes from catalog metadata): skipped (deferred) for a
marketplace whose Step 1 refresh failed — see Step 1.

Take `fleet-state.sh`'s `missing_from_enabled` (`--marketplace "$mp" --ids missing-enabled` emits the
id list directly — see Step 3) — ids installed somewhere but never mentioned (true
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
the sources the "Version capture for the report" section above fixes.

**Split the Divergences count into pre-existing and run-caused.** A user-scope sweep that moves user
scope ahead of untouched project records *manufactures* actionable divergences — the run's own
correct consequence, not drift it discovered. Reporting the total as a single discovered number
routes the user to `converge` for skew this run just created.

**Attribute it to the right step — that needs THREE snapshots, not two.** Steps 2 and 3 both mutate
versions, so a single pre-Step-2 / post-Step-3 bracket cannot tell which one created a new
divergence, and labelling the whole delta "the user-scope sweep" is wrong whenever Step 2 caused it.
Concretely: equal project and user records at `v1`, Step 2 updates the project record to `v2`, Step 3's
user update fails — the skew is Step 2's, and a two-snapshot diff blames Step 3. Take the
`divergences[]` read from each of the three `fleet-state.sh` calls the algorithm already makes — the
pre-Step-2 snapshot, the pre-Step-3 re-read the concurrency rule requires anyway, and the post-sweep
re-read — and attribute each new row to the interval it first appeared in. No extra call is needed;
this is bookkeeping over reads that already happen.

Report as
`<N> actionable (<M> newly created by this run — <a> by the in-repo update, <b> by the user-scope
sweep, <N-M> pre-existing)`. When the two intervals genuinely cannot be separated (a snapshot was
missed), say `<M> newly created by this run` without splitting it, rather than assigning the whole
delta to one step.

**Say when the sweep updated `claude-ops` itself.** Step 3 sweeps every user-scope id, which
necessarily includes the plugin providing this skill. When it does, the algorithm that ran is the
**pre-update** one: `${CLAUDE_PLUGIN_ROOT}` keeps resolving to the version loaded at session start,
so every later `fleet-state.sh` call and every remaining step executes the old copy, and the report
describes work done by a version the user no longer has installed. Current docs, `plugins-reference`
(fetched 2026-08-22): "When a plugin updates mid-session, hook commands, monitors, MCP servers, and
LSP servers keep using the previous version's path." This is not a crash risk — the previous version
directory is retained on a grace period, so the running script does not vanish mid-run — it is a
reporting obligation. Emit SKILL.md's self-update row.

End with reload guidance per SKILL.md's Report section: recommend bare `/reload-plugins`, and state
the recovery step rather than pre-judging which case will trigger it. Call out a session restart
separately only when an updated component ships a monitor (monitors aren't covered by
`/reload-plugins`).
