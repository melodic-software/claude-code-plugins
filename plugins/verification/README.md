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

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure verification@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install verification@<marketplace> -s <scope> --config proof_level=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

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

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
