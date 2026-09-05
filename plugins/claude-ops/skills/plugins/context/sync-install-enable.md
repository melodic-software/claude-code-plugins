# Sync Steps 4 and 5 — install and enable

Read this file only when the **fresh pre-Step-4 `fleet-state.sh` re-read** for the marketplace being
swept — the live read [sync.md](sync.md)'s "Steps 4 and 5" section takes and saves as
`$run_dir/pre-install.$mp.json` — has a non-empty `missing_from_user_install` **or** a non-empty
`missing_from_enabled`, or when Step 1's refresh failed for that marketplace and the report has to
name what these two steps deferred. On an already-current fleet both arrays are empty, both steps
are no-ops, and none of this is reachable. The gate deliberately keys on that re-read rather than
Step 1's older report, because state can change between the two; see sync.md for why.

The steps below are the loop body of [sync.md](sync.md) Steps 2–5, run once per marketplace, and
every rule that file states — CLI-mediated mutation only, the per-marketplace failure rule, the
re-read boundary at the step, the projection shape and its exit-status check, and the
`rc=${PIPESTATUS[0]}` capture after every `tee`-journaled mutating call — applies here unchanged.
Each mutating call below is journaled and status-captured in exactly the shape sync.md's "Run
journal" section fixes; that shape is not restated here.

## Contents

- [Step 4 — Install new catalog plugins (per `install_new` policy)](#step-4--install-new-catalog-plugins-per-install_new-policy)
- [Step 5 — `enabledPlugins` completeness](#step-5--enabledplugins-completeness)

## Step 4 — Install new catalog plugins (per `install_new` policy)

Catalog-dependent: skipped (deferred) for a marketplace whose Step 1 refresh failed — see
[sync.md](sync.md) Step 1.

This step's live `fleet-state.sh --marketplace "$mp"` re-read — the one the
re-read-before-each-mutating-step rule requires — has already happened: it is the read that gated
loading this file, saved to the run journal as `pre-install.$mp.json`. Project the ids from that
file rather than reading a third time. `--from` replaces the SECOND process this step used to
launch, never the re-read itself:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh \
  --ids missing-user-install --from "$run_dir/pre-install.$mp.json" \
  >"$run_dir/ids.pre-install.$mp.txt"
rc=$?   # exit 2 with empty output is a FAILED projection, not "nothing to install"
```

Check `rc` before looping the file, per sync.md's projection section: a `--from` rejection exits 2
with empty stdout, which a loop alone cannot tell apart from an empty install list.

Take `fleet-state.sh`'s `missing_from_user_install` from that projection (see
[sync.md](sync.md) Step 3 for why the ids never come from a hand-written `jq`) — catalog ids not
installed at `user` scope
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
"Action needed" list rather than in the scrollback — see SKILL.md's Report section for the slot. It
also belongs in the run journal, per [sync.md](sync.md)'s "Run journal" section: this is a mutating
call, and its output is the only record of what it said.

### After any install — normalize user-scope `enabledPlugins` key order

Claude Code's settings writer appends each new `enabledPlugins` key at the end of the map rather
than inserting it alphabetically. The rest of the map is sorted, so every sync that installs
something leaves an unsorted tail that never self-heals and churns diffs for anyone whose
`~/.claude/settings.json` is managed.

There is no `claude plugin` verb that reorders the map. After this step installs **anything**,
run the bundled normalizer against the user-scope file only:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/normalize-enabled-plugins.sh
```

Override the path with `--file` or `FLEET_STATE_USER_SETTINGS` when the run is not using the
machine default (same override `fleet-state.sh` honors).

- **User scope only.** The write is a strict key reorder: keys and values byte-identical, order
  alone changed. It is consistent with what this step already does — Step 5 already writes
  `~/.claude/settings.json` via `claude plugin enable -s user`.
- **Never normalize project scope.** That is the committed, team-shared file the Scope invariant
  protects. If a project-scope map is unsorted, report it under Action needed and stop:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/normalize-enabled-plugins.sh \
    --report-project "${project_root}/.claude/settings.json"
  ```

  `project-unsorted` is a report row, not a write. `converge` remains the only action that may
  touch that file.
- **Never silent.** A `normalized keys=N` result becomes the report's `Normalized:` row. A
  `refused:` result (permission denial, unreadable JSON, a semantic diff) becomes an Action
  needed bullet — fail loudly, never skip. `--check` is the audit-mode stand-in (predict
  `would-normalize`, write nothing).
- **Skip the write when this step installed nothing.** An already-sorted map is a no-op either
  way (`already-sorted`); the reorder exists to heal the tail this step just created.

## Step 5 — `enabledPlugins` completeness

Catalog-dependent (`defaultEnabled` comes from catalog metadata): skipped (deferred) for a
marketplace whose Step 1 refresh failed — see [sync.md](sync.md) Step 1.

**This step takes its own live re-read — it cannot reuse Step 4's.** Step 4 mutated in between: it
installed plugins and normalized the user-scope `enabledPlugins` map, so `pre-install.$mp.json` no
longer describes the state this step is about to act on. Save the new read as `pre-enable.$mp.json`
and project from it:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh --marketplace "$mp" \
  >"$run_dir/pre-enable.$mp.json"

"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh \
  --ids missing-enabled --from "$run_dir/pre-enable.$mp.json" \
  >"$run_dir/ids.pre-enable.$mp.txt"
rc=$?   # exit 2 with empty output is a FAILED projection, not "nothing to enable"
```

Check `rc` before looping the file, for the reason Step 4 gives.

Take `fleet-state.sh`'s `missing_from_enabled` from that projection — ids
installed somewhere but never mentioned (true
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
that file (verified on Claude Code 2.1.228, re-verified unchanged on 2.1.261 — see [scope-semantics.md](scope-semantics.md)), so this
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
