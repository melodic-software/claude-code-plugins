# engineering-concepts

Shipped concepts: software engineering concepts (principles, patterns, practices and
architectures) kept as data. Each record is a short pointer to the concept's official source, never
a copied definition, tagged so a session can find the concepts that apply to the work in front of
it. The catalog states no positions: whether to follow a concept is a team's or person's stance,
kept in their own standards layers.

**No curated concepts ship yet.** The catalog's data directory is empty until owner-reviewed
records are added, so every lookup currently finds nothing.

## Skills

| Skill | What it does |
|---|---|
| `/engineering-concepts:lookup` | Finds records by name, alias, id or tag and reports their sources, counterweights and conflicts |
| `/engineering-concepts:load` | Brings a topic or one entry into the session as working context |
| `/engineering-concepts:adopt` | Writes chosen entries into a personal or team standards file and adds the file's index row |

## Data

One JSONL file per topic under `data/`, one record per line. A record carries:

| Field | Meaning |
|---|---|
| `id` | Readable kebab-case slug, minted once and never changed; a merged id stays as an alias of the surviving record |
| `name`, `aliases[]` | What the concept is called; lookups match either, whatever the case |
| `concern`, `kind` | What the concept is about and what sort of thing it is |
| `stage` | `interview`, `design`, `plan`, `build`, `review`, `operate` or `any` |
| `reversibility` | `one-way`, `two-way` or `unrated` |
| `source_url` | The official source, `https://` |
| `confirming_sources[]` | Optional further sources that agree with it |
| `owner` | The skill (`/plugin:skill`) or page that owns the practice in depth |
| `counterweights[]`, `conflicts_with[]` | Ids of concepts that pull against or contradict it |

A record that fails these rules is reported on stderr with its file and line, and the others load.

## Lookup script

`scripts/lookup.mjs` reads only the plugin's data. Its `--help` lists the filters and options. It
prints one JSON record per line, with `counterweights` and `conflicts_with` given as `{id, name}`.

`--check-sources` is the one mode that touches the network: it fetches each record's `source_url`
and marks one that fails with `needs_resourcing: true`, keeping the record. Run it by hand or on a
schedule and read its report; tests never run it against the network.

## Adopt script

`scripts/adopt.mjs` writes adopted standards: the entries a person or team chose, each as a line
naming the concept, its id and its official source. Counterweights and conflicts are not copied:
`lookup.mjs --counterweights-of <id>,<id>` prints one line per counterweight or conflict for the
ids a file cites, so a consuming stage reads them from the shipped data at load time. It writes `<surface>.md` into the personal layer (`~/.claude/standards/`) or the team
layer (the repository's standards root) and adds that file's row to the layer's index. Without
`--yes` it only prints what it would write. The files follow the
[standards contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/standards/README.md#standards-files):
no frontmatter, one concern per file. Its `--help` lists the options and exit codes.

## Settings

Two settings resolve through the plugin config cascade, lowest first: the plugin default, the
plugin's options below, the team file `docs/conventions/engineering-concepts.yaml` (or the
repository's own convention home), and the personal override `engineering-concepts.local.yaml`
beside it. The schema is `schemas/engineering-concepts.schema.json`.

- `source_bar`: the highest layer that sets a valid value wins. An invalid value is reported and
  the setting falls back to the default, not to a lower layer.
- `exclude`: every layer's list is unioned, together with any `--exclude` on the command line. As
  a plugin option it is one comma-separated string; in the YAML files it is a list.

```yaml
source_bar: official-plus-confirming
exclude:
  - some-concept-id
  - some-topic
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `source_bar` | string | `"official"` | Which catalog records lookups return: official (every record with an official source) or official-plus-confirming (only records that also list a confirming source). docs/conventions/engineering-concepts.yaml overrides this. |
| `exclude` | string | *(none)* | Comma-separated concept ids or topic names that lookups drop. Unioned with every exclude list in docs/conventions/engineering-concepts.yaml and its .local.yaml. |

### How to set these

Set the options above for `engineering-concepts@<marketplace>`, replacing `<marketplace>` with the
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
