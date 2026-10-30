# verification

A Claude Code plugin for the **verification stage** of a disciplined dev workflow. It proves a change achieved its intended outcome, and proves measurable-improvement claims
against a baseline captured before the change. Three skills, one concern: turning a
green build into confirmed outcomes.

| Skill | What it does |
|---|---|
| `/verification:confirm` | Outcome verification, a mechanical prerequisite gate (delegated to build/lint) followed by intent-match + evidence + verdict, with the criterion auto-detected by change-type (feature / fix / refactor). |
| `/verification:measure` | Measurable-improvement verification. Capture a baseline at planning time, re-measure after the change under the same conditions; no baseline → honest "cannot quantify", never fabricated numbers. |
| `/verification:setup` | Report where verification artifacts land and validate the repository's proof level; `apply` writes `docs/conventions/verification.yaml` after confirmation. Re-runnable. |

## Works in any repo

- **Delegates the mechanical pass, degrades gracefully.** `/verification:confirm`
  delegates its build/test/lint prerequisite to the `toolchain` plugin's
  `/toolchain:check` and `/toolchain:lint` when installed, and runs the project's own
  ecosystem-native commands otherwise. The STOP-on-fail gate is unchanged; only the
  executor differs. Live-app verification prefers the `testing` plugin's
  `/testing:run-e2e` when installed and falls back to Claude Code's bundled `/run` or a
  manual orchestrator launch, never silently downgrading to a static check.
- **Never fabricates a measurement.** `/verification:measure` requires a baseline
  captured before the change; with none, it reports an honest "cannot quantify" plus a
  current-state measurement, never an invented delta.
- **Document placement, via the artifact protocol.** Verification manifests, baselines and
  raw captures land per the plugin's lifecycle artifact protocol
  (`reference/artifact-protocol.md`): in the self-ignoring `<memory_dir>/<slug>/` (default
  `.work/<slug>/`), never committed. Distilled, `verified_at_sha`-keyed manifests are pasted into
  the pull request body or the linked issue.
- **Self-contained.** Criterion context files ship inside the plugin and
  are referenced via `${CLAUDE_PLUGIN_ROOT}`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install verification@melodic-software
```

## Configuration

Artifact placement is fixed by the artifact protocol, so it is not configured.
`/verification:setup check` reports the effective memory root read-only.

One setting, `proof_level` (`path`, `live` or `strict`, default `path`), decides how much evidence
`/verification:confirm` needs before `CONFIRMED`. Set it per user through the plugin option below
and per repository in `docs/conventions/verification.yaml` (schema
`schemas/verification.schema.json`, written by `/verification:setup apply`). The stricter of the
two wins, and the repository value is read from the default branch, so a branch cannot lower it.
A second setting, `live_workers` (a whole number, default 1), sets how many workers split that live
drive by feature-map entry point, at the same two levels with the repository value winning; a
release without it runs one worker.
Keys, layers and resolution: `reference/config.md`.

**Upgrade every member before setting a floor.** A verification release from before this setting
does not read `docs/conventions/verification.yaml`, so on that machine a repository's `live` or
`strict` silently weakens to the `path` rule. Each run's proof-level line names the level and its
source, so a reviewer can spot a run that lacks it.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `proof_level` | string | `"path"` | `CLAUDE_PLUGIN_OPTION_PROOF_LEVEL` | Evidence /verification:confirm requires. path (default): a live run only for runtime-affecting paths. live: a live drive for any change with a runnable surface. strict: unit, live and performance proof per phase. The stricter of this and the default branch's docs/conventions/verification.yaml wins. |
| `live_workers` | number<br>*min 1* | `1` | `CLAUDE_PLUGIN_OPTION_LIVE_WORKERS` | How many workers /verification:confirm splits its live drive across, by feature-map entry point; default 1. Above 1 on one machine it needs a Workspace environment entry on the default branch, else one worker runs. A repository's docs/conventions/verification.yaml wins. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure verification@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure verification@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"proof_level": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install verification@<marketplace> -s <scope> --config proof_level=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "verification@<marketplace>": {
         "options": {
           "proof_level": <value>
         }
       }
     }
   }
   ```

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
