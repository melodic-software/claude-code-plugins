# Melodic Software — Claude Code plugins

A public plugin marketplace of reusable, repo-agnostic skills, hooks, and agents for
[Claude Code](https://code.claude.com/docs) and [Cursor](https://cursor.com/docs/plugins).
Each plugin is designed to work in any repository and to be customized by consumers without
editing the plugin itself.

## Use this marketplace

### Claude Code

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install <plugin-name>@melodic-software
```

Browse and manage with `/plugin`. To refresh after updates: `/plugin marketplace update melodic-software`.

### Cursor

Cursor reads [`.cursor-plugin/marketplace.json`](https://cursor.com/docs/reference/plugins)
(generated from the Claude catalog — do not hand-edit). Add the GitHub repo as a personal
marketplace in **Customize**, or import it as a [Team Marketplace](https://cursor.com/docs/plugins#team-marketplaces)
from **Dashboard → Plugins** if you have admin access:

1. Add `https://github.com/melodic-software/claude-code-plugins`.
2. Install individual plugins from Customize (user or workspace scope).
3. After catalog updates on `main`, refresh the marketplace in Customize. If the UI stays
   pinned to an old commit (a known Cursor personal-marketplace issue), remove the marketplace,
   delete `~/.cursor/plugins/marketplaces/github.com/melodic-software/` and
   `~/.cursor/plugins/cache/melodic-software/`, reload the window, and re-add the repo.

Claude-specific hooks and `userConfig` fields are not portable to Cursor; skills, agents,
commands, rules, and MCP configs in the shared plugin directories are.

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

- `.claude-plugin/marketplace.json` — Claude Code marketplace catalog (SSOT).
- `.cursor-plugin/marketplace.json` — Cursor marketplace catalog (generated; run
  `node scripts/generate-cursor-manifests.mjs`).
- `plugins/` — one directory per plugin (`plugins/<name>/.claude-plugin/plugin.json` is SSOT;
  `plugins/<name>/.cursor-plugin/plugin.json` is generated).
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
