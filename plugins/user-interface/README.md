# user-interface

Front door for interface design. An agent building anything a person or agent interacts with (CLI
output, a TUI, a prompt theme, a Claude Code mod, web or app UI) gets guidance that keeps the
project's existing look, reuses the design tools already installed, and fills only the gaps.

| Skill | What it does |
|---|---|
| `/user-interface:design` | Detect the project's design system and the installed design tools, route each concern to the best present source, and supply the plugin's own guidance where nothing covers it |

## How it routes

For each concern the order is:

1. The project's own design system, conventions and MCP servers.
2. This repository's enabled plugins.
3. Official publishers.
4. Community tools, with adoption breaking ties.
5. This plugin's own guidance.

The routes live in [`reference/routing.json`](reference/routing.json), validated by
[`reference/routing.schema.json`](reference/routing.schema.json).
[`scripts/detect.mjs`](scripts/detect.mjs) reports what the project and machine have, and which
installed routes are reachable.

## Guidance

- [`reference/principles.md`](reference/principles.md): the working order, the usability heuristics,
  and the accessibility floor every medium keeps.
- [`reference/types/`](reference/types/): one file per interface type. The skill reads the file
  that matches, so a new type is a new file.
  - [`terminal.md`](reference/types/terminal.md): CLI output, TUIs, prompt themes, PowerShell,
    banners; `NO_COLOR`, non-TTY output and plain-text fallbacks.
  - [`mods.md`](reference/types/mods.md): Claude Code mod displays, building on terminal.md.
  - [`web.md`](reference/types/web.md) and [`app.md`](reference/types/app.md): project-first rules
    and pointers to platform guidelines.

## Options

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `account_tools_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_ACCOUNT_TOOLS_ENABLED` | Route to tools that need an account, login or API key (Claude Design, Figma, axe) when installed and reachable; false uses only account-free tools. Paid tools only when nothing free fits. No effect yet: every account-bound route is still deferred until it is tested. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure user-interface@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install user-interface@<marketplace> -s <scope> --config account_tools_enabled=<value>
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
       "user-interface@<marketplace>": {
         "options": {
           "account_tools_enabled": <value>
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
