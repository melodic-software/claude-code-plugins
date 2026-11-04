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
  `schemas/domain-driven-design.schema.json`) and the personal override
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

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `glossary_file` | string | `"GLOSSARY.md"` | File name curate-language proposes for a bounded context's glossary when the repository has no glossary convention. A file name, never a path. docs/conventions/domain-driven-design.yaml overrides this. |
| `glossary_map_file` | string | `"GLOSSARY-MAP.md"` | File name curate-language proposes for the root context map once more than one bounded context exists. A file name, never a path. docs/conventions/domain-driven-design.yaml overrides this. |

### How to set these

Set the options above for `domain-driven-design@<marketplace>`, replacing `<marketplace>` with the
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

As of 2026-11-04. Recheck trigger: one of these sections moves, or a Claude Code
release note changes how plugin options are set or stored.

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
