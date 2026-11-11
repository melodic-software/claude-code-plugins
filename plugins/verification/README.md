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

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `proof_level` | string | `"path"` | Evidence /verification:confirm requires. path (default): a live run only for runtime-affecting paths. live: a live drive for any change with a runnable surface. strict: unit, live and performance proof per phase. The stricter of this and the default branch's docs/conventions/verification.yaml wins. |
| `live_workers` | number<br>*min 1* | `1` | How many workers /verification:confirm splits its live drive across, by feature-map entry point; default 1. Above 1 on one machine it needs a Workspace environment entry on the default branch, else one worker runs. A repository's docs/conventions/verification.yaml wins. |

### How to set these

Set the options above for `verification@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
