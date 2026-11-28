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

`audit` runs `/harness-ops:plugins sync`'s algorithm through `sync-run.sh --audit`: every mutating
CLI call becomes a prediction, no state file is written, and the scratch directory holding its
step reports is removed when the call returns. It is its own skill so the model may start it;
`sync` and `converge` stay user-only in `/harness-ops:plugins`.

Everything else about the run is the plugins skill's: in `${CLAUDE_PLUGIN_ROOT}/skills/plugins/SKILL.md`,
target resolution under "Marketplace resolution" and the report rules under "Report"; and what
each step does and why in `${CLAUDE_PLUGIN_ROOT}/skills/plugins/context/sync.md`, the step
sequence this run executes. Read that file when the digest meets one of its triggers or the user
asks why a step behaved as it did; in it `<skill-dir>` means `${CLAUDE_PLUGIN_ROOT}/skills/plugins`.

## Run it

The first token of `$ARGUMENTS`, after removing `--allow-downgrade` wherever it sits, is an
optional target: a marketplace name, or `all`; with none the script resolves the default. An
audit never passes `--allow-downgrade`; when the user gives it, say the audit ignores it.

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/sync-run.sh \
  [--marketplace <name> | --all] --audit \
  --install-new '${user_config.install_new}' \
  --quiet-auto-update '${user_config.quiet_auto_update_marketplaces}' [--update-other-paths] --render
```

That path is exact and the script lives in the `plugins` skill, so run it as written with no search
for it.

- Run the two option values as they appear here: each holds the configured value, or the unset
  placeholder token, which the single quotes keep from the shell and the script reads as that
  option's default.
- Pass `--update-other-paths` only when the **Configured value** line under "userConfig:
  `update_other_paths`" reads `true`.
- Never pass `--journal-root`, `--pull-source` or `--only-install`: they are `sync` requests.

The output is the digest line, a blank line, then the rendered report. The scratch directory is
gone when the call returns, so answer follow-up questions from the printed digest.

## Report

Before presenting it, read the Report section of `${CLAUDE_PLUGIN_ROOT}/skills/plugins/SKILL.md`
and paste the rendered report by its rules.

**The prediction is a lower bound.** An audit issues no `marketplace update`, so its Step 3
prediction is computed against an unrefreshed catalog and carries that catalog's `lastUpdated`. An
audit that predicts zero updates has not established that the fleet is current.

## userConfig: `update_other_paths`

Whether `sync` also updates the lagging records of every other present path, which the audit then
predicts one by one.

**Configured value: `${user_config.update_other_paths}`**. The unset placeholder token means the
default, `false`.

## Next

- Predictions the user wants applied: /harness-ops:plugins sync.
- A reported divergence: /harness-ops:plugins converge.

## Related

- Checking upstream plugin staleness and alternatives: /harness-ops:audit-plugin-landscape.
- Auditing project settings against upstream catalogs: /harness-config:audit.
