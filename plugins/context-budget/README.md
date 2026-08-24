# context-budget

Measure a Claude Code session's fixed startup context payload **per item**, on your machine, at a
pinned binary, and record what every trim actually saved.

`/context` already itemises skills, agents, and MCP tools. What it structurally cannot itemise is
the built-in tool pool: `System tools` and `System tools (deferred)` are lump sums, and together
they are typically the largest single contributor to the fixed payload. This plugin attributes
them per tool by A/B differencing: a baseline headless session versus one session per candidate
tool with that tool denied by bare name. The deltas are compositional, so a basket of trims can be
priced from its members.

## Install

```text
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install context-budget@melodic-software
```

## Skills

- `/context-budget:setup`. Read-only prerequisite check: `node` (the hook launches it by bare
  name, and a launch failure is non-blocking, so the checkpoint can be configured on yet never
  fire), the `claude` CLI the engine measures against, the optional Agent SDK that enables exact
  mode, and the effective `settings_write_ask_enabled` value. Installs nothing.
- `/context-budget:audit`. Take a stamped baseline snapshot, attribute the built-in tool pools
  over the live tool list, present catalogue levers with their honesty categories, and ledger
  any before/after the operator produces. Read-only on bare invocation: it prints exact config
  (for persistent denies, a `permissions.deny` entry) and applies nothing. With the explicit
  `fix` argument, a guided per-lever walkthrough may edit **project** settings after per-diff
  approval. User-global `~/.claude/settings.json` is only ever printed, and every applied lever
  is re-measured and ledgered before the next.

## Hook

A PreToolUse checkpoint returns `permissionDecision: "ask"` for any Write/Edit targeting a
Claude Code settings surface, so settings edits prompt even in auto mode. It is a checkpoint,
not a guarantee (a `PermissionRequest` hook can allow the call; `disableAllHooks` removes
non-managed hooks). Kill switch: the `settings_write_ask_enabled` plugin option.

## What makes the numbers trustworthy

- **Nothing is shipped, everything is measured.** The skill contains no token figures, tool
  inventories, or thresholds. Those drift with every CLI release. Every number in a report was
  produced by a run on the consumer's machine during that audit.
- **Every report is stamped** with the measured binary path and version, the measurement mode,
  and the session kind. Machines with two CLI installs get an answer per binary, not a blend.
- **Comparability is enforced, not advised.** `System tools` deltas are only valid between runs
  with identical skill listings (listed skill frontmatter is subtracted from that bucket); the
  engine fingerprints the listing per run and marks violating comparisons incomparable rather
  than reporting their numbers.
- **Levers are catalogued data, not folklore.** Each row in
  `skills/audit/reference/levers.json` carries its honesty category (does it remove weight, work
  but save nothing here, block without saving, sit as vendor weight, or cost more than it buys),
  the official citation behind it, how to detect and measure it, the exact config it would emit,
  and a recheck trigger. A lever whose category cannot be determined for your configuration is
  not offered.
- **Honest degradation.** Exact mode uses the Agent SDK's structured context usage. Without the
  SDK, the engine parses headless `/context` output version-aware (display-rounded, and flagged
  as resting on an undocumented surface). When neither works, it emits a structured error with a
  remediation, never a wrong number.

## Prerequisites

- `node` (required, the engine's runtime).
- The Claude Code CLI (`claude` on PATH, or pass the engine an explicit `--binary`).
- Optional, for exact mode: `@anthropic-ai/claude-agent-sdk`, installed once into the plugin's
  data directory (the audit skill offers the command; it is the operator's call since it needs
  network access).

## Data

Ledger and snapshots live under `${CLAUDE_PLUGIN_DATA}/audit/<state-key>/`, keyed per project by
the marketplace's shared state-key scheme, with one file per run plus an appended history line.
Uninstalling the plugin from its last scope deletes this directory unless `--keep-data` is
passed.

## Boundaries

- Usage-based removal ("which plugins do I never use") belongs to the bundled `/doctor`; the
  skill routes there and never reimplements it.
- Per-skill / per-agent / per-MCP-tool attribution belongs to `/context` natively.
- Live in-session occupancy zones belong to the `context-guard` plugin.
- Measurements describe **headless** sessions of the **local CLI**; interactive sessions and
  cloud/web surfaces can compose the payload differently, and reports say so.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `settings_write_ask_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED` | Kill switch for the PreToolUse hook that forces a permission prompt (permissionDecision ask) on any Write/Edit targeting a Claude Code settings surface |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure context-budget@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install context-budget@<marketplace> -s <scope> --config settings_write_ask_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "context-budget@<marketplace>": {
         "options": {
           "settings_write_ask_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->
