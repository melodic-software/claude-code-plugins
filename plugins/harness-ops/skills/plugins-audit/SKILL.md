---
description: "Read-only dry run of /harness-ops:plugins sync: predicts the marketplace refreshes, updates, installs, enables and scope divergences sync or converge would act on, and issues none of those calls. Its update count is a lower bound against the unrefreshed catalog. Use when: 'are my plugins current', 'check plugin drift', 'audit my plugins', 'what would plugin sync do', or before relying on a plugin that might be stale."
argument-hint: "[<marketplace>|all]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Predict what plugin sync would change, read-only
  cadence: weekly
---

## Variables

Arguments: `$ARGUMENTS`

## Scope

`audit` runs the same algorithm as `/harness-ops:plugins sync`, with every mutating CLI call
replaced by a prediction. It reads the fleet through `fleet-state.sh`, computes the same
install, enable and divergence deltas, and issues **zero**
`claude plugin install|update|uninstall|marketplace update` calls. It reports the scope
divergences `converge` would reconcile, with that remedy, and runs no part of `converge`. It
writes no state file
(`installed_plugins.json`, `known_marketplaces.json`, a settings file); a concurrent session or a
background `autoUpdate` sweep can still change them while it runs.

This skill is model-invocable because it changes nothing. `sync` and `converge` stay in
`/harness-ops:plugins`, which only the user starts: a sync can update committed plugin pins in
every repository on disk.

**A read that sits beside a mutating call is still taken.** Step 1's pre-refresh `fleet-state.sh`
snapshot is a read, so `audit` takes it, and only the `claude plugin marketplace update` beside it
becomes a prediction. That snapshot is the first link in the catalog regression check's chain; an
audit that skipped it would start the check at `pre` and lose the interval that isolates the
refresh point.

The script writes its step reports to a throwaway `mktemp -d` scratch directory, created before
Step 1 and deleted when the run ends, never to the durable run journal. That keeps one algorithm
for both actions while leaving nothing behind.

## Arguments

Remove `--allow-downgrade` from `$ARGUMENTS` first, wherever it sits. The first remaining token is
an optional marketplace target: a marketplace name, or `all`. With none, the
target is the marketplace this plugin was installed from, which `fleet-state.sh` resolves from
`${CLAUDE_PLUGIN_ROOT}`; no marketplace name is hardcoded. `all` covers every marketplace in
`known_marketplaces.json`, and a failure in one is reported inline without aborting the rest.

`--allow-downgrade` is a `sync` flag, and an audit never passes it. When the user gives it, say the
audit ignores it: an audit issues no update either way and predicts
`Would withhold: <N> downgrade(s)` beside `Would update` regardless.

## Run it

Substitute the target and the configured values below into one call:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/sync-run.sh \
  [--marketplace <name> | --all] --audit \
  --install-new <policy> [--quiet-auto-update <names>] --render
```

That path is exact and the script lives in the `plugins` skill, so run it as written with no search
for it.

- `<policy>` is the word on the **Configured value** line under "userConfig: `install_new`":
  `all`, `none` or `ask`, and `ask` while that line shows the unset placeholder token. Pass the
  word, never the token: a placeholder inside a command is a shell substitution error. Any other
  word is treated as `ask` and named back in the digest's `install_new_invalid`.
- `--quiet-auto-update` takes the names on the **Configured value** line under "userConfig:
  `quiet_auto_update_marketplaces`". Leave the flag out while that line shows the placeholder
  token or nothing.
- Never pass `--journal-root`, `--pull-source` or `--only-install`: they are `sync` requests, and
  the script refuses the last two under `--audit`.

The first line of output is one compact JSON digest; after a blank line comes the rendered report.
Both live in the scratch directory, which is gone when the call returns, so answer follow-up
questions from the printed digest.

## Report

Paste the rendered report as printed. Do not restate a number, an id, a scope or a count it
already carries, and do not add rows: a row the render omitted is a row whose digest field was
empty, which is not proof that nothing happened. When something in the run suggests more than the
render shows (a `Not verified:` row, or `Moved during this run:` ids), you may add one caveat line
stating what the report cannot establish, never a cause.

The verdict line reads `Result: see the predictions below, nothing under Action needed`, or
`Result: no change predicted, a lower bound against the unrefreshed catalog`, or counts the
`Action needed` items. Every call `sync` would make carries the `would run:` prefix. A remedy
`sync` never runs itself (a `git -C <path> pull --ff-only`, a project-scope enable) reads unprefixed.

**The prediction is a lower bound.** An audit issues no `marketplace update`, so its Step 3
prediction is computed against an unrefreshed catalog and carries that catalog's `lastUpdated`. An
audit that predicts zero updates has not established that the fleet is current.

**The one line you own is the reload guidance**, appended after the render: recommend bare
`/reload-plugins`, and `/reload-plugins --force` only when the bare command warns. Never recommend
`--force` up front: it opts into a token cost the bare command declines to pay.

To act on a prediction, the user runs `/harness-ops:plugins sync` (or `converge` for a divergence)
themselves.

Load `${CLAUDE_PLUGIN_ROOT}/skills/plugins/context/sync.md` when the digest carries errors, a
catalog regression, a cache-content finding, or a nonzero `moved_during_run` or `noop_unverified`
count, or when the user asks why a step behaved as it did. It is the step sequence this run
executes. `${CLAUDE_PLUGIN_ROOT}/skills/plugins/context/stale-records-cache-content.md` covers a
nonzero `stale_project_records.total` or `cache_content.stale_content`. In those files `<skill-dir>`
means `${CLAUDE_PLUGIN_ROOT}/skills/plugins`, and "SKILL.md" means that skill's SKILL.md.

Only for a question about a state no render in hand shows,
`${CLAUDE_PLUGIN_ROOT}/skills/plugins/scripts/render-report.jq` holds the row rules, at that exact
path. Rows the user already has are the report: quote them as given and never check them against it.

## userConfig: `install_new`

The new-catalog-plugin policy `sync` would apply, which the audit predicts against: `ask`
(default; the gap is reported for the user to choose from), `all` (would install every
not-yet-installed catalog plugin) or `none` (reported only). Under `all` with the `all` target,
the predicted install gap is every plugin in every known catalog: state that count plainly, since
`sync` would install all of it.

**Configured value: `${user_config.install_new}`**. The value renders only when the key is set in
user settings, `--settings` or managed settings; an unset key leaves the literal placeholder token,
which means the default, `ask`, and is not an invalid value. The probe record behind that reading is
`${CLAUDE_PLUGIN_ROOT}/skills/plugins/context/scope-semantics.md`.

## userConfig: `quiet_auto_update_marketplaces`

Comma-separated marketplace names whose `Marketplace:` line shows `autoUpdate: off` without the
suggestion to enable it.

**Configured value: `${user_config.quiet_auto_update_marketplaces}`**. The unset placeholder token,
or nothing, means no names: leave the flag out.

## Next

- Apply what the audit predicts: `/harness-ops:plugins sync` (user-invoked).
- Reconcile a reported divergence: `/harness-ops:plugins converge` (user-invoked).
