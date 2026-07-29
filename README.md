# Melodic Software — Claude Code plugins

A public [Claude Code](https://code.claude.com/docs) plugin marketplace of reusable, repo-agnostic
skills, hooks, and agents. Each plugin is designed to work in any repository and to be customized by
consumers without editing the plugin itself.

## Use this marketplace

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install <plugin-name>@melodic-software
```

Browse and manage with `/plugin`. To refresh after updates: `/plugin marketplace update melodic-software`.

### Enable plugin suggestions for an organization

Some catalog entries declare `relevance` signals so Claude Code can suggest the plugin when a
session's work matches (matching runs locally; nothing is reported anywhere). Suggestions are
opt-in per marketplace: they surface only after an administrator allowlists the marketplace in
[managed settings](https://code.claude.com/docs/en/settings#settings-files) — declare the
marketplace source AND allowlist its name in the same file:

```json
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": {
        "source": "github",
        "repo": "melodic-software/claude-code-plugins"
      }
    }
  },
  "pluginSuggestionMarketplaces": ["melodic-software"]
}
```

The source declaration is required for any non-official marketplace: the allowlisted name is
ignored if the locally registered marketplace came from a different source, which stops an
unrelated catalog from registering under an allowlisted name to get its plugins suggested.
Reference: [Recommend plugins for your org](https://code.claude.com/docs/en/plugin-relevance).

A few personal or external-service plugins install disabled (`defaultEnabled: false`) until the
user opts in with `/plugin enable`; an existing install is never flipped by catalog changes.

## Finding your way

- Not sure which skill to invoke? Start at the [skill cheat sheet](docs/SKILL-CHEAT-SHEET.md) — a
  scan-and-go map from what you're doing to the skill to use.
- [Plugin catalog](docs/CATALOG.md) — every plugin by category, generated from the manifests and
  kept in sync by CI. New plugins clear the per-plugin migration gate in
  [`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md).
- [Catalog taxonomy](docs/CATALOG-TAXONOMY.md) — the category vocabulary the catalog is grouped by.

## What's here

- `.claude-plugin/marketplace.json` — the marketplace catalog.
- `plugins/` — one directory per plugin.
- `docs/MIGRATION-PLAYBOOK.md` — design charter, extensibility model, the per-plugin migration
  gate, and the local development loop.
- `docs/` — further design records and audits (CI runner routing, extensibility-contract smoke
  tests, migration audits).
- `CLAUDE.md` — operating rules for AI agents working in this repo (fresh-docs mandate + plugin
  design rules).
- `docs/OFFICIAL-DOCS.md` — canonical index of the official Claude Code doc pages the mandate
  sends you to.

## Official documentation

This repo tracks policy and wiring only; authoritative behavior lives in the official docs, which must
be read fresh rather than recalled. Start at the
[Claude Code plugins guide](https://code.claude.com/docs/en/plugins).

## License

[MIT](LICENSE).
