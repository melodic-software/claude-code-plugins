# domain-driven-design

A Claude Code plugin owning **DDD practice skills**. It holds the stewardship
disciplines of domain-driven design, independent of any one planning or workshop
workflow.

| Skill | What it does |
|---|---|
| `/domain-driven-design:curate-language` | Actively maintains the consuming project's ubiquitous-language glossary: resolves ambiguous or overloaded terms, records canonical language and rejected synonyms, sharpens definitions to say what each term is, and routes entries to already-known bounded contexts. It never discovers boundaries itself. |

Deferred: `context-mapping` and `aggregate-design` join this plugin when those
practices materialize as skills.

Bounded-context **discovery** is out of scope here. Workshop-driven discovery lives in
the standalone `event-storming` plugin, which `curate-language` soft-routes to when
boundaries are missing.

## Works in any repo

- **Reads your conventions first.** Glossary filename, location, shape, and context map
  come from the consuming project. Where none exist, it proposes, never imposes, one
  `GLOSSARY.md` per bounded context and a root `GLOSSARY-MAP.md` once more than one
  context exists, and writes only after you confirm; creation stays lazy.
- **Settings.** `glossary_file` and `glossary_map_file` set those two names. They
  resolve through the config cascade: the plugin default, `userConfig`, the team file
  `docs/conventions/domain-driven-design.yaml` (schema
  `schemas/domain-driven-design.schema.json`) and the personal overlay
  `docs/conventions/domain-driven-design.local.yaml`. Each is a file name, never a path.
- **No persistent state, no network.**

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install domain-driven-design@melodic-software
```

The `planning` plugin invokes `/domain-driven-design:curate-language` when it is installed, and
records resolved terms in its own artifacts when it is not. Install this plugin alongside
`planning` to get glossary stewardship inside the planning workflow.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `glossary_file` | string | `"GLOSSARY.md"` | `CLAUDE_PLUGIN_OPTION_GLOSSARY_FILE` | File name curate-language proposes for a bounded context's glossary when the repository has no glossary convention. A file name, never a path. docs/conventions/domain-driven-design.yaml overrides this. |
| `glossary_map_file` | string | `"GLOSSARY-MAP.md"` | `CLAUDE_PLUGIN_OPTION_GLOSSARY_MAP_FILE` | File name curate-language proposes for the root context map once more than one bounded context exists. A file name, never a path. docs/conventions/domain-driven-design.yaml overrides this. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure domain-driven-design@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install domain-driven-design@<marketplace> -s <scope> --config glossary_file=<value>
   ```

   Rerun the same command to change a value on an installed plugin, passing the scope
   `claude plugin list` reports for this plugin. Do **not** `claude plugin uninstall` to
   reconfigure: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
   The [`plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure) entry in the CLI reference covers applying a saved
   value. What a rerun prints and writes, and why a session started before the rerun keeps the
   old value until a fresh session starts, are recorded in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "domain-driven-design@<marketplace>": {
         "options": {
           "glossary_file": <value>
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
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
