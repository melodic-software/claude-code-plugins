---
description: "Bring a machine's plugin fleet current on demand: marketplace refresh, update the plugins that actually load (including in-repo project/local-scope installs), install new catalog plugins per policy, detect scope divergence, and surface (never silently fix) drift, with a terse actionable report; refuses to downgrade by default. Actions: sync (default, mutating), audit (read-only dry run), converge (explicit scope consolidation). Use when: 'sync plugins', 'update my plugins', 'are my plugins current', 'check plugin drift', 'converge plugin scopes', or before relying on a plugin that might be stale."
argument-hint: "[action] [<marketplace>|all] [--allow-downgrade]. Actions: sync (default), audit, converge"
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

**For `sync` and `audit`, the script computes every number and the model reports it.** Steps 1
through 5b and the Step 6 render are one `sync-run.sh` call; the digest and the rendered report
are the record, and the model adds the reload guidance and answers questions. Nothing in the
report is retyped, recounted, or re-derived by the model. `converge` stays model-driven until it
gains a script of its own, so this invariant does not yet cover it.

**The skill never branches on the host to change its algorithm or its report.** There is no
cloud-versus-local branch, and no detection of or coordination with a repository's bootstrap hook:
the same steps run and the same report renders wherever the skill is invoked. Two things this
invariant does not cover, because they are not algorithm or report branches: the destructive-tier
autonomy abort `converge` performs before touching anything (`CLAUDE_CODE_REMOTE`, `/loop`,
`/schedule`; see [context/converge.md](context/converge.md)), and the platform-portability
detection in `fleet-state.sh` (`$OSTYPE` for MSYS and Cygwin path forms), which changes how a path
is spelled and never what is computed.

## Action Router

Parse `$ARGUMENTS` for the action (first token) and an optional marketplace target (second token:
a marketplace name, or `all`).

`--allow-downgrade` is position-independent: remove it from `$ARGUMENTS` first, then apply the
first-token / second-token parse to what remains, so it reads the same before, between, or after the
other two. It applies to `sync` only, and it opts that run into moving an install backward when the
marketplace catalog reads lower than what is installed. `audit` ignores the flag and says so in its
report: a read-only run issues no update either way, and its prediction already names the withheld
downgrades. See [context/sync.md](context/sync.md)'s "Downgrade guard".

This table is an index, not a substitute: read the linked detail file before executing any action.
Each Description names the territory an action covers, never its algorithm, the steps, their
ordering, and their failure handling live only in the linked file.

One block below is a deliberate exception to that index-only rule and has to live in the hub
rather than in a spoke: the **`install_new` render**, because Claude Code substitutes
`${user_config.*}` when it renders the *skill*; a spoke opened later as a file read is plain bytes,
so the same token in a spoke would arrive as a literal placeholder with no error to warn anyone.
See [context/gotchas.md](context/gotchas.md). The Report section below is a pointer: the report
itself is rendered by the script.

| Action | Mutates | Description | Detail |
|---|---|---|---|
| `sync` (default) | Yes. CLI only | Marketplace, install, and enable-state maintenance for the effective fleet | [context/sync.md](context/sync.md) |
| `audit` | No | Same algorithm as `sync`, every mutating CLI call replaced with a prediction; the reads those calls sit beside still run | "Action: audit" below |
| `converge` | Yes. Can rewrite committed settings after confirm | Cross-scope divergence reconciliation, preview- and confirm-gated | [context/converge.md](context/converge.md) |

Bare invocation (no arguments) → `sync` against the default marketplace. `help` or an unrecognized
action → show this table.

## Running `sync` and `audit`

Both actions execute Steps 1 through 5b and render Step 6's report as ONE bundled script call:
it prints the JSON digest, then the report. The step sequence, and the reason behind every step,
stay in [context/sync.md](context/sync.md); the script is bound to that file.

1. **Run it.** Substitute the marketplace target, the policy, and the flags into this command. The
   journal root is written here because `${CLAUDE_PLUGIN_DATA}` resolves in skill content and
   **not** in a `context/*.md` spoke, which is read raw:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/sync-run.sh \
     [--marketplace <name> | --all] \
     --journal-root "${CLAUDE_PLUGIN_DATA}/plugins-sync/runs" \
     --install-new <policy> [--allow-downgrade] --render
   ```

   `audit` is the same command with `--audit` instead of `--journal-root` (it writes to a scratch
   directory it deletes) and never `--allow-downgrade`, which it ignores and says so.

   `<policy>` is the word from the **Configured value** line under "userConfig: `install_new`"
   below: `all`, `none`, or `ask`, and `ask` when that line still shows the unset placeholder
   token. Pass the WORD, never the token: a placeholder inside a command is a shell substitution
   error, not a policy. Any other value is treated as `ask` and named back in the digest's
   `install_new_invalid` so the report can flag it.

2. **Read the output.** The first line is one compact JSON digest, also written to
   `<run_dir>/digest.json`; after a blank line comes the rendered report, also written to
   `<run_dir>/report.txt`. The digest carries a `run_dir` that holds every snapshot and the
   journal, and the fields the `ask` re-entry needs.

3. **Resolve an `ask` install gap.** When a block has a non-empty `install_gap` and
   `stopped_before_install: true` (the report says so under `Action needed`), run the batched
   multi-select from [context/sync-install-enable.md](context/sync-install-enable.md), then
   re-enter for Steps 4 and 5 against the same run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/sync-run.sh \
     --only-install "<the ids the user picked, comma-separated>" --run-dir "<the digest's run_dir>" --render
   ```

   An empty id list is legal and means "install nothing, still complete Step 5". The report that
   call prints supersedes the first one, covers the whole run, and reuses the same cache-content
   finding rather than checking again.

4. **Report.** Paste the rendered report and append the one model-owned line; see the Report
   section below.

Load [context/sync.md](context/sync.md) when a digest carries errors, a non-empty gap, a catalog
regression, or a cache-content finding, and when the user asks why a step behaved the way it did.
A run with none of those has nothing in the file that changes the report.

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

`sync-run.sh` above is what calls these scripts during `sync` and `audit`; the contracts below are
what it and any other caller are bound to.

A second read-only script answers the question `fleet-state.sh` structurally cannot: whether the
files in a plugin's cache directory actually match the commit its install record claims. Step 5b of
`sync` and of `audit` calls it ONCE per marketplace:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/cache-content-check.sh --marketplace <name> [--scope user|project|all]
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/cache-content-check.sh --marketplace <name> --ids
```

`--ids` emits the stale ids alone, one per line, CR-free, the same contract and for the same reason
as `fleet-state.sh --ids`. Step 5b does not use it beside the JSON form: the ids are already in that
JSON, and a second call would repeat the run's most expensive read. It is the fallback for a JSON
that could not be produced. The script never writes anything and never runs `git fetch`; a commit
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

**A read that sits beside a mutating call is still taken.** Step 1 is the case that matters: its
pre-refresh `fleet-state.sh` snapshot is a read and `audit` takes it, and only the
`claude plugin marketplace update` beside it becomes a prediction. That snapshot is the first link in
the catalog regression check's chain, so an `audit` that skipped it would start the check at `pre`
and lose the interval that isolates the refresh point. See [context/sync.md](context/sync.md) Step 1.

`audit` runs the same steps, and those steps write reports from Step 1's snapshot onward, so it does
write them: to a throwaway `mktemp -d` scratch directory, created before Step 1 and deleted when the
run ends, never to the durable run journal under this plugin's data directory. That keeps one algorithm
for both actions while leaving nothing behind, which is what "mutates nothing" means here. See
[context/sync.md](context/sync.md)'s "Run journal" section.

`audit` ignores `--allow-downgrade` and says so when the flag is passed: it issues no update in
either case, and it predicts `Would withhold: <N> downgrade(s)` beside `Would update` regardless.
See [context/sync.md](context/sync.md) Step 3.

Because `audit` issues no `marketplace update`, its Step 3 prediction is computed against an
**unrefreshed** catalog and is therefore a lower bound on what `sync` would update. Report it as one,
carrying the catalog's `lastUpdated`. See [context/sync.md](context/sync.md) Step 3. An `audit`
that predicts zero updates has not established that the fleet is current.

## Report

Step 6 is rendered by the script. `sync-run.sh --render` prints the fixed-section report after the
digest line, every run writes the same text to `<run_dir>/report.txt`, and
`jq -r -f "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/render-report.jq <run_dir>/digest.json`
reproduces it from a run directory later. Every section, conditional row, annotation, and
`Action needed` bullet is a function of digest fields, which is what keeps a number, an id, or a
scope from being misstated between the run and the report: the `Marketplace:` line with its
three-way `autoUpdate` slot (`on`; `off` with the suggestion to enable it; `unreadable` for a
`null`, never rendered as off); the fixed `In-repo:` row in its three variants (`skipped` naming
the cwd when no project root resolved, `0` naming a root with no project/local installs, and the
counted variant, forward moves only); `Updated:` (forward moves and pairs flagged
`(direction unknown)`) and `Downgraded:`; `Catalog regression:`; `Installed:` with the policy-`all`
recurrence clause; `Normalized:`; `Enabled:`; the `Divergences:` split, led by this project's count
when a root resolved; the self-update note when the sweep moved this plugin; the stale project
records and cache content sections; the `Timing:` row (the marketplace total and its slowest step,
with the clock's resolution; a measurement with no threshold); and `Action needed` (install and
enable gaps, failed CLI calls, user-scope orphans, installs that left userConfig options unset,
updated plugins whose installed build declares a monitor, reorder refusals, an unsorted
project-scope map, withheld downgrades with both versions and the likely cause, and every error).
In `audit` mode every mutating line carries the `would run:` prefix and `Would withhold:` sits
beside `Would update:` whether or not a downgrade was found; `--allow-downgrade` is named as
ignored. Each shape is pinned to a golden file under `scripts/fixtures/render/` by
`scripts/sync-run.test.sh`.

Paste the render as printed. Do not restate a number, an id, a scope, or a count it already
carries, and do not add rows: a row the render omitted is a row whose digest field was empty. Per
marketplace in `all` mode the whole block repeats, because Steps 2 through 5 run once per
marketplace; the trailing `Run journal:` and `Timing:` lines cover the invocation.

**The one line the model owns is the reload guidance**, appended after the render and stated as
the docs' own two-step rather than as a prediction about which case will trigger it: recommend bare
`/reload-plugins`; if it warns that the reload would re-read the conversation, rerun it as
`/reload-plugins --force`. The general condition `--force` exists for is prompt-cache
invalidation; a plugin shipping an MCP server whose tools aren't deferred is the common cause, not
the only one, so do not present it as the sole trigger and do not tell the user `--force` would be
wrong when the bare command has already warned them. Never recommend `--force` pre-emptively
alongside every reload: it opts into a real token cost the bare command declines to pay on its own
(see [context/scope-semantics.md](context/scope-semantics.md)). Monitors are already covered: the
render's `Action needed` names each updated plugin whose installed build declares one and
attributes "monitors require a session restart" to the plugins reference, so the reload line does
not repeat it. After the line, answer follow-up questions from the digest and the run directory it
names; load [context/sync.md](context/sync.md) when a question is about why a step behaved the
way it did.

(A plugin updated mid-session keeps resolving to the previous version's path, which is what the
self-update note reports. `plugins-reference`, re-fetched 2026-09-05 and unchanged; behaviour
observed on Claude Code 2.1.240 and not re-run on 2.1.261, because it needs an interactive session.
See [context/gotchas.md](context/gotchas.md).)

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
carries an `enabledPlugins` block mirroring what the user already has at user scope writes one
project record per `true` entry at the first session start in that checkout, pinned to the version
the user scope holds (verified on Claude Code 2.1.263). A `false` entry writes nothing. Report the
count and the distinct paths, and name the block as the source when the path's repo carries one.
[context/scope-semantics.md](context/scope-semantics.md) "Where project-scope records come from, and
why the skill cannot reap them" holds the sourcing, the precedence rule, the reap boundary, and the
probe recipe that established the write.

The render gives the section a count plus the distinct paths, not one row per record, because a
hundred records naming a dozen directories is a report about a dozen directories: `K` is
`stale_project_records.total`, `P` is the length of `stale_project_records.by_path`, and each
`by_path` entry is the `{path, count}` one row renders. The section is omitted when `K` is 0.

A project-scope enable gap is a row `sync` deliberately does not fix. Step 5 enables automatically
only where the write is not team-shared state. The render lists each one under `Action needed` as
its runnable command, `(cd "<projectPath>" && claude plugin enable <id>@<marketplace> -s project)`,
with the note that it writes that repo's committed `.claude/settings.json`, so acting on it is a
copy, not a reconstruction. Only ids that Step 5 did not enable at `user`/`local` scope in this run
appear there. For the rest the command would fail rather than run, and Step 5 explains why.

When a project root resolved, the render leads the `Divergences:` line with *this* project's
actionable count and folds the rest of the machine into one trailing clause, e.g. `2 behind here
→ converge; 27 more elsewhere on this machine`. Per-row detail (naming exact `<old> → <new>`
versions per repo) is reserved for genuine conflicts: an unknown/orphaned plugin id, or a CLI call
that failed, never for the routine bulk case. (Enable-state mismatches, a plugin `true` in one
scope's `enabledPlugins` and `false` in another, are a known blind spot, not a reportable category:
`fleet-state.sh` only exposes the merged effective value, never each scope's raw map, so this skill
cannot detect one to report it. See [context/converge.md](context/converge.md) "V1 scope".)

## Cache content. Reported, never repaired

A version-and-sha check is not proof that the files on disk are the build the record names. When a
plugin's manifest version does not change across a commit, `claude plugin update` re-points the
record's `gitCommitSha` and leaves the existing version directory in place, so the metadata claims
the new commit while the directory still holds the old build. See
[context/scope-semantics.md](context/scope-semantics.md) for the observation this rests on.

Step 5b runs `cache-content-check.sh`, which byte-compares every file in each cache directory
against the recorded commit in the marketplace clone. The render omits the `Cache content:` row
when it finds nothing. When it finds something, the render names the ids and gives the remediation
that was actually proved to work, rather than a suggestion: remove that version's directory under
the plugin cache, then re-run `claude plugin update <id>@<marketplace>`, which recreates it from
the clone.

`N` is `cache_content.stale_content`, and one row comes from each `cache_content.stale[]` entry:
`id`, `version`, and `files_differ`, which sums every direction of disagreement: bytes that
changed, files the tree has and the cache lacks, and files the cache holds and the tree does not.
`files_differ` reads `null` when the digest fell back to the checker's `--ids` form, which knows the
ids and no per-file detail; the row then carries the id alone.

**The check never repairs.** It does not delete a cache directory, does not re-run an update, and
does not `git fetch` a commit the marketplace clone lacks. A commit that is not local is reported as
`sha-not-local` and left alone: fetching is a network mutation this audit does not perform, and it
would also silently erase the condition the verdict exists to report. Every verdict other than
`match` and `stale-content` is counted as `unverifiable`, meaning the audit looked and could not decide,
which is its own number and never folded into either side.

**Expect a substantial `unverifiable` share, and never read it as a pass.** Claude Code clones a
marketplace shallow, so any install whose recorded commit predates that clone's window reports
`sha-not-local` through no fault of the fleet. On the machine this check was first run against, 11
of 74 user-scope installs were unverifiable for exactly that reason. The render says so alongside
the match count rather than leading with the match count alone: a row with the unverifiable share
when nothing is stale, and a sub-line under the finding when something is.

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
an unset key (first verified 2026-07-23 against CC 2.1.218, **re-verified 2026-09-06 against CC
2.1.263**: an unset key leaves the placeholder token unchanged, the same shape as
`${user_config.…}`, while a sibling key set in `~/.claude/settings.json` and `${CLAUDE_PLUGIN_ROOT}`
both substitute in the same render). The current `plugins-reference` page says the manifest
`default` "is used if specified" for an unset key; the 2.1.263 render contradicts that for skill
content, so this skill keeps trusting the probe over the page. **Recheck trigger:** re-verify on any
Claude Code minor-version bump that touches plugin `userConfig` substitution, or when
`plugins-reference` changes its unset-key wording.

When re-running that probe, the `pluginConfigs` payload must nest the key under `options`
(`{"pluginConfigs":{"<id>@<marketplace>":{"options":{"<key>":"<value>"}}}}`); a key placed directly
under the plugin id is ignored without warning, and a control set that way renders literal, which
looks exactly like a substitution failure. With the right shape, `--settings` substitutes the same
as user settings (verified 2026-09-06 on 2.1.263, alongside a sibling key set in user settings), so
either source is a valid positive control. `claude plugin install <id> --config <key>=<value>`
writes the user-settings entry in that shape, which is the cheapest way to set one. So for the common
default-config user, with no `pluginConfigs` set anywhere, the **Configured value** line above still
shows that literal placeholder token, not `ask`.

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
