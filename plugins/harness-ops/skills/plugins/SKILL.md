---
description: "Bring a machine's plugin fleet current on demand: marketplace refresh, update the plugins that actually load (including in-repo project/local-scope installs), install new catalog plugins per policy, detect scope divergence, and surface (never silently fix) drift, with a terse actionable report; refuses to downgrade by default. Actions: sync (default, mutating), converge (explicit scope consolidation); the read-only dry run is /harness-ops:plugins-audit. Use when: 'sync plugins', 'update my plugins', 'converge plugin scopes'."
argument-hint: "[sync|converge] [<marketplace>|all] [--allow-downgrade] [--update-other-paths]"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: operator
  summary: Bring the machine's plugin fleet current. Refresh, update, install per policy
  cadence: weekly
---

**Arguments.** `[sync|converge] [<marketplace>|all] [--allow-downgrade] [--update-other-paths]`. Actions: sync (default; alias update), converge. The read-only `audit` is its own skill, `/harness-ops:plugins-audit`; this skill is user-only because `sync` can update the project and local plugin pins of every repository on disk

## Variables

Arguments: `$ARGUMENTS`

## Scope

Guarantees that the plugins which actually load, at user scope and in the repo you stand in, are
the latest published versions of everything the marketplace offers, and surfaces any state where
something older or unintended is what really runs.

Distinct from Claude Code's background `autoUpdate`, which we treat as a refresh of installed
plugins, never a substitute ([context/scope-semantics.md](context/scope-semantics.md) holds that
reading): this skill also installs new catalog plugins, checks `enabledPlugins` completeness,
reports scope divergence, and runs on demand.

Distinct from `harness-config`'s `audit` plugin-drift check, which compares committed
`enabledPlugins` against a marketplace's *upstream* `marketplace.json`: this skill compares the
*local* installed state against the *local* catalog.

**Never silently fixes drift it finds.** `sync` mutates only via the documented CLI actions below,
plus the one `git pull --ff-only` of a `directory` source the user agreed to (see "userConfig:
`directory_source_pull`"). It never writes a committed `.claude/settings.json`: Step 5 enables
automatically only at `user` and `local` scope and reports a `project`-scope gap, and after Step 4
installs anything it may reorder only the user-scope `~/.claude/settings.json` map, never a
project-scope one. `converge` is the one action that can touch committed settings, and only after
an explicit per-plugin confirm. See [context/scope-semantics.md](context/scope-semantics.md) for
which CLI calls write that file.

**The scripts compute every number and the model reports it.** For `sync` and the audit, Steps 1
through 5b and the Step 6 render are one `sync-run.sh` call, and nothing in the report is retyped,
recounted or re-derived. `converge-plan.sh` computes every `converge` row's strategy, command and
class, grouped by path; the model presents it and runs only what the user confirms.

**The skill never branches on the host to change its algorithm or its report**: no cloud-versus-local
branch and no coordination with a repository's bootstrap hook. Outside that invariant are the two
uses of the autonomy test below and `fleet-state.sh`'s `$OSTYPE` check, which changes how a path
is spelled, never what is computed.

**The autonomy test.** A session fails it, meaning no human is there to answer a question, when
`CLAUDE_CODE_REMOTE` is set, when the invocation arrived via `/loop` or `/schedule`, or when it is
unclear a human is present. `sync-run.sh` checks the `CLAUDE_CODE_REMOTE` half itself; the model
checks the rest. On a session that fails it, `converge` aborts before touching anything, and `sync`
neither offers nor runs a `directory`-source pull.

## Action Router

Parse `$ARGUMENTS` for the action (first token) and an optional marketplace target (second token:
a marketplace name, or `all`).

`--allow-downgrade` is position-independent: remove it from `$ARGUMENTS` before that parse. It
applies to `sync` only, and opts the run into moving an install backward when the catalog reads
lower than what is installed ([context/sync.md](context/sync.md) "Downgrade guard").

This table is an index: read the linked detail file before executing any action, except `sync`,
which one script runs and which loads its file on the triggers under "Running `sync`". Steps, their
order and their failure handling live only in the linked file.

The **`${user_config.*}` tokens** in step 1's command and the **Configured value** line are the
deliberate exception and must stay in the hub: we rely on `${user_config.*}` being substituted only
when Claude Code renders the *skill*, so in a spoke read as a file the token arrives as a literal
placeholder with no error. See [context/gotchas.md](context/gotchas.md).

| Action | Mutates | Description | Detail |
|---|---|---|---|
| `sync` (default) | Yes. CLI only | Marketplace, install, and enable-state maintenance for the effective fleet | [context/sync.md](context/sync.md) |
| `converge` | Yes. Can rewrite committed settings after confirm | Cross-scope divergence reconciliation, preview- and confirm-gated | [context/converge.md](context/converge.md) |

Bare invocation → `sync` against the default marketplace. `update` is an alias for `sync`. `audit`
→ run nothing here and point the user to `/harness-ops:plugins-audit`. `help` or an unrecognized
action → show this table.

## Running `sync`

One script call runs Steps 1 through 5b and renders Step 6's report; the step sequence and the
reason behind every step stay in [context/sync.md](context/sync.md).

1. **Run it.** Substitute the marketplace target and the flags into this command. The journal root
   is written here because `${CLAUDE_PLUGIN_DATA}` resolves in skill content, never in a spoke:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/sync-run.sh \
     [--marketplace <name> | --all] \
     --journal-root "${CLAUDE_PLUGIN_DATA}/plugins-sync/runs" \
     --install-new '${user_config.install_new}' \
     --source-pull '${user_config.directory_source_pull}' \
     --quiet-auto-update '${user_config.quiet_auto_update_marketplaces}' \
     [--allow-downgrade] [--update-other-paths] --render
   ```

   Run the three option values as they appear here: each holds the configured value, or the
   unset placeholder token, which the single quotes keep from the shell and the script reads as
   that option's default. Pass `--source-pull never` instead on a session that fails the autonomy
   test. A value the script does not know runs as `ask` and is named in the report.

2. **Read the output.** The first line is one compact JSON digest (also `<run_dir>/digest.json`),
   then a blank line and the rendered report (also `<run_dir>/report.txt`). The digest's `run_dir`
   holds every snapshot, the journal and what the `ask` re-entry needs.

3. **Resolve a pull offer.** When a block's `source_pull.status` is `offered`, ask the user once
   per such marketplace whether to fast-forward its checkout (one `AskUserQuestion` question per
   marketplace, Pull or Skip). A session that fails the autonomy test never gets here: its first
   run had `--source-pull never` and offers nothing. On a yes, run the step 1 command again with
   `--pull-source "<the names the user agreed to, comma-separated>"` added: the script rechecks
   each checkout and fast-forwards it with `git pull --ff-only` before its refresh, or refuses with
   the reason and touches nothing. Its report supersedes the first, so read the next step from its
   digest. A no or no answer keeps the first report and its pull-and-rerun bullet. Ask once per
   invocation: a declined marketplace stays `offered` in later digests and is not asked about
   again. Resolve this before step 4, so the install gap comes from the current checkout.

4. **Resolve an `ask` or held install gap.** When a block has a non-empty `install_gap` and
   `stopped_before_install: true` (the report says so under `Action needed`), ask the questions
   its `install_offer` lists, worded per
   [context/sync-install-enable.md](context/sync-install-enable.md), then re-enter for Steps 4 and
   5 against the same run. The re-entry installs each pick and enables any the CLI installed
   disabled by default:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/sync-run.sh \
     --only-install "<the ids the user picked, comma-separated>" --run-dir "<the digest's run_dir>" --render
   ```

   A dismissed or unanswered question declines only its own ids: leave them out and keep the
   answered questions' picks. When nothing was answered, re-enter with `--only-install ""`, which
   installs nothing, still completes Step 5, and lists the declined gap under `Action needed`. The
   re-entry's report supersedes the first and covers the whole run, its cache-content check
   included.

5. **Report.** Paste the rendered report; see the Report section below.

Load [context/sync.md](context/sync.md) when a digest carries errors, a non-empty gap, a catalog
regression, a cache-content finding, a refused or failed `source_pull`, or a nonzero
`moved_during_run` or `noop_unverified` count, and when the user asks why a step behaved as it did.

## Marketplace resolution

No hardcoded marketplace name anywhere in this skill. Every action resolves its target the same way:

- No marketplace argument → the marketplace this plugin was installed from, which `fleet-state.sh`
  resolves from `${CLAUDE_PLUGIN_ROOT}` and the install records.
- `<marketplace-name>` argument → that marketplace only.
- `all` argument → every marketplace in `known_marketplaces.json`; a per-marketplace failure is
  reported inline and never aborts the sweep. Under a policy of `all` this target installs
  nothing on its own: the script holds the gap (`install_held: "all-target"`) for step 4's offer.

## State inspection

Every action reads the fleet through the read-only `fleet-state.sh`, checks cache content through
`cache-content-check.sh`, and reorders a user-scope `enabledPlugins` map only through
`normalize-enabled-plugins.sh`. Never hand-parse `installed_plugins.json`,
`known_marketplaces.json`, or a settings file, never write them, and never hand-write a `jq`
extraction where a script's `--ids` form exists. `converge`'s committed-enable check
([context/converge.md](context/converge.md) Step 2) reads each path's `enabledPlugins` entry from
`fleet-state.sh`'s `projectEnabledEntry`, never from the file. `scripts/jq-capture.sh` (the
CR-stripping `jq` capture and JSON string encoder the scripts share) and
`scripts/snapshot-ledger.sh` (the run's snapshot lookup) are sourced libraries, never invoked. Read
[context/script-contracts.md](context/script-contracts.md) when a step misbehaves, when `converge`
needs an id list, or before invoking a script from anywhere other than `sync-run.sh`; it carries
each script's invocation forms and the `\r` rule behind `--ids`.

## The read-only audit

`/harness-ops:plugins-audit` runs `sync-run.sh --audit`, every mutating call predicted. It is a
separate skill so the model may start it, since `disable-model-invocation` covers a whole skill.

## Operator script: refresh and clean

`scripts/reset-refresh.sh` re-fetches the user-scope fleet with its configuration unchanged. It
refuses to run beside a live session, so when the user asks for it, give them these commands to
run from a terminal with every session closed, and run none:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/reset-refresh.sh preview
bash "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/reset-refresh.sh refresh
bash "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/reset-refresh.sh clean
```

[context/refresh.md](context/refresh.md) holds what each level does and its safeguards.

## Report

The script renders Step 6 and writes it to `<run_dir>/report.txt`;
`jq -r -f "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/render-report.jq <run_dir>/digest.json`
reproduces it later, or prints one line pointing at `report.txt` for a digest of another
`digest_version`.

Every row is a function of digest fields: [scripts/verdict.jq](scripts/verdict.jq) classifies,
[scripts/render-report.jq](scripts/render-report.jq) holds the row rules, and the goldens under
[scripts/fixtures/render/](scripts/fixtures/render/) record every shape the report takes. Why a row
says what it says lives in [context/sync.md](context/sync.md) and
[context/stale-records-cache-content.md](context/stale-records-cache-content.md). The `Result:`
verdict counts `Action needed` items only; a `remedy:` on another row still applies.

Paste the render as printed. Do not restate a number, an id, a scope, or a count it already
carries, and do not add rows: an omitted row is an empty digest field, not proof that nothing
happened. The initial report may add one caveat line when the run suggests more than the render
shows (a `not verified:` row, or `moved during this run:` ids): state what the report cannot
establish, never a cause. The render ends with the reload guidance whenever the run changed what
this session loads; add no reload advice of your own
([context/scope-semantics.md](context/scope-semantics.md) "`/reload-plugins`: bare by default,
`--force` for the MCP-cache-invalidation case" holds why).

Answer follow-up questions from the digest (its `verdict` objects hold the report's status,
pending, changed and `Action needed` facts) and the run directory it names; load
[context/sync.md](context/sync.md) when a question is about why a step behaved the way it did.

## Stale project records and cache content

Both are findings the render reports and this skill never fixes: a record whose `projectPath` is
not present is never counted as a divergence, suppressed or reaped, and a cache directory whose
files disagree with the recorded commit is named with its proved remediation, never repaired
([context/stale-records-cache-content.md](context/stale-records-cache-content.md)).

## userConfig: `install_new`

New-catalog-plugin install policy during `sync`: a `string` whose `options` picker lists the three
values below, default `"ask"`. The script still validates it, since a value set by hand in
`settings.json` skips the picker
([Limit a field to fixed options](https://code.claude.com/docs/en/plugins/manifest-reference#limit-a-field-to-fixed-options);
[context/scope-semantics.md](context/scope-semantics.md) holds the option-schema record):

- `ask` (default). Offer every not-yet-installed catalog plugin by asking the questions the
  digest's `install_offer` lists, one `AskUserQuestion` call per entry
  ([context/sync-install-enable.md](context/sync-install-enable.md) Step 4 holds how each question
  reads). Then install and enable each pick, including one the CLI installs disabled by default.
  An unanswered or dismissed question counts as declined
- `all`. Install every not-yet-installed catalog plugin automatically; one the CLI installs
  disabled by default stays off and is reported
- `none`. Report them in "Action needed" only, never install

Any other set value runs as `ask` and is named in the report. With the `all` target an `all`
policy installs nothing on its own (see "Marketplace resolution";
[context/gotchas.md](context/gotchas.md) has the incident).

We treat each `${user_config.*}` token in step 1's command as rendering the configured word only
when the key is set in a scope Claude Code reads `pluginConfigs` from
([settings reference: pluginConfigs](https://code.claude.com/docs/en/settings-reference#pluginconfigs)),
never a project's `.claude/settings.json` or `.claude/settings.local.json`; an unset key leaves the
literal placeholder token, which `sync-run.sh` reads as the default.
[context/scope-semantics.md](context/scope-semantics.md) "`userConfig`: an unset key renders the
literal placeholder" holds the read path and the probe record: read it when a rendered value looks
wrong.

## userConfig: `directory_source_pull`

What `sync` does with a `directory` marketplace whose git checkout is clean (no modified tracked
files), on a branch with an upstream, not ahead of it and behind it. A `string` with the picker
values below, default `"ask"`, read and rendered the same way as `install_new` above:

- `ask` (default). The digest marks such a checkout `offered`, and step 3 of "Running `sync`"
  asks and reruns with `--pull-source` on a yes. Any other checkout is never offered, and the
  script refuses a `--pull-source` for one, so the pull cannot discard or tangle local work.
- `never`. Nothing is offered or pulled, and the report keeps its pull-and-rerun bullet.

A session that fails the autonomy test runs as `never` whatever the value. A word other than these
two runs as `ask` and is named in the report.

## userConfig: `update_other_paths`

Whether `sync` also updates the lagging project and local records of every other present path. A
`boolean`, default `false`: off, the report counts them and names the remedy. Pass
`--update-other-paths` when the **Configured value** line below reads `true` or the user gave the
flag, which is position-independent like `--allow-downgrade`. [context/sync.md](context/sync.md)
Step 3a says why it is off by default.

**Configured value: `${user_config.update_other_paths}`**. The unset placeholder token here means the
default, `false`.

## userConfig: `quiet_auto_update_marketplaces`

Comma-separated marketplace names whose `Marketplace:` line shows `autoUpdate: off` without the
suggestion to enable it. A `string`, default empty; step 1 passes it as `--quiet-auto-update`.

For the option fields, the picker and where a value is stored, see
[User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

## Spoke paths

The `context/` files write this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`:
put that path in its place before running a command or writing it into a brief. Those files carry
no `${…}` token, since we rely on neither substitution in a Read result nor `CLAUDE_SKILL_DIR` in
the Bash tool's environment.

- **Pointer**: for where each `${…}` reference resolves, see
  [Where each variable resolves](https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves).

## Next

/harness-ops:prerequisites lists which external binaries the enabled fleet is missing.

## Related

- Read-only dry run before syncing: /harness-ops:plugins-audit.
- Checking stale upstreams and plugin alternatives: /harness-ops:audit-plugin-landscape.

## Reference index. Load on demand

| File | Load when |
|---|---|
| [context/sync.md](context/sync.md) | A `sync` digest meets a trigger under "Running `sync`", or the user asks why a step behaved as it did. |
| [context/sync-install-enable.md](context/sync-install-enable.md) | A digest block has a non-empty `install_gap` or `enable_gap`, or `install_enable_deferred: true`. |
| [context/converge.md](context/converge.md) | Running `converge`. |
| [context/stale-records-cache-content.md](context/stale-records-cache-content.md) | The digest's `stale_project_records.total` or `cache_content.stale_content` is above 0, or the user asks why either section reads as it does. |
| [context/script-contracts.md](context/script-contracts.md) | A step misbehaves, `converge` needs an id list, or a caller other than `sync-run.sh` is about to invoke a script. |
| [context/scope-semantics.md](context/scope-semantics.md) | A scope, version, or reload claim needs its verified source before you act on it; also the `userConfig` unset-key probe record. |
| [context/refresh.md](context/refresh.md) | The user asks about refresh or clean, or about `reset-refresh.sh`'s output. |
| [context/gotchas.md](context/gotchas.md) | A run failed in a way the steps do not explain, or a safeguard looks removable. |
