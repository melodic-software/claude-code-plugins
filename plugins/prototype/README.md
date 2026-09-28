# prototype

A Claude Code plugin for building **throwaway code that answers a design question** before you
commit to architecture. A prototype proves "X works like THIS" cheaply. You push buttons, watch
state change or flip between designs, keep the answer, and delete the code.

It ships **two skills**, split by the shape of the question you're answering:

| Skill | Invoke | Answers |
|---|---|---|
| `pressure-test` | `/prototype:pressure-test <scope>` | "Does this state machine / data model / API surface feel right?", an interactive terminal app driving a portable, liftable logic module by hand. |
| `explore-directions` | `/prototype:explore-directions <scope>` | "What should this look like?". Several radically different visual variations on one route, switchable from a floating control bar (real stack, a self-contained HTML mockup, or, where the bundled `design` skill is available, an editable design-canvas Artifact, offered as an explicit opt-in). |

Both skills share one throwaway discipline (no persistence, skip polish, surface the state, delete
or absorb when done) and both capture the validated answer in a durable note before the code is
thrown away.

## When to use which

- **Logic** is a behavioral / feasibility spike, the question is about business logic, state
  transitions, or data shape. It produces a **pure logic module** behind a disposable TUI shell;
  when the question is answered, the module lifts into production and the shell is deleted.
- **UI** is a design prototype, the question is about appearance. It generates structurally
  different variants (not just recolors) so you can judge them side by side, then fold the winner
  into the real page.

Each skill auto-invokes on its own trigger phrases, or you can call it directly. If you're not sure
which fits, a backend/logic question routes to `pressure-test` and a page/component question routes to `explore-directions`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install prototype@melodic-software
```

## Configuration

This plugin has no `userConfig`. Its only inputs are conversational, the scope you pass and the
variant count you ask for (UI defaults to 3, capped at 5). It reads your project's own stack and
conventions rather than imposing its own, and it writes throwaway code next to where your
production code lives.

## Requirements

- **Bash** for the bundled ecosystem-detection script. On native Windows,
  install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  it runs under Git Bash. Without Bash, detection reports "none detected" and
  the skills read the host project directly to pick the stack.

Prototypes are built in whatever language and task runner your host project
already uses; the plugin adds no runtime of its own.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `medium` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_MEDIUM` | Preferred medium for this plugin's rendered views. auto uses each skill's shipped default. terminal, file, and artifact select that rung of the rendered-views ladder. An unrecognized value is reported and treated as unset. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure prototype@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install prototype@<marketplace> -s <scope> --config medium=<value>
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
       "prototype@<marketplace>": {
         "options": {
           "medium": <value>
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

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
