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
3. MCP plugins that need credentials declare Cursor [`variables`](https://cursor.com/docs/reference/plugins#variables);
   set values under **Plugins → Configure** (generated `mcp.json` uses `${VAR}` placeholders).
4. After catalog updates on `main`, refresh the marketplace in Customize. If the UI stays
   pinned to an old commit (a known Cursor personal-marketplace issue), remove the marketplace,
   delete the local mirror + cache, reload the window, and re-add the repo:
   - macOS/Linux: `~/.cursor/plugins/marketplaces/github.com/melodic-software/` and
     `~/.cursor/plugins/cache/melodic-software/`
   - Windows: `%USERPROFILE%\.cursor\plugins\marketplaces\github.com\melodic-software\` and
     `%USERPROFILE%\.cursor\plugins\cache\melodic-software\`

**Portability (from official docs):** Claude `userConfig` / `${user_config.*}` /
`${CLAUDE_PLUGIN_ROOT}` are Claude Code contracts
([plugins reference](https://code.claude.com/docs/en/plugins-reference)). Cursor MCP uses
generated `mcp.json` + `variables` / `${VAR}`
([plugins reference](https://cursor.com/docs/reference/plugins)). Claude hook *settings*
can load in Cursor via [third-party hooks](https://cursor.com/docs/reference/third-party-hooks);
Claude *plugin* `hooks/hooks.json` is a different surface. For plugins that ship Claude
plugin hooks, the Cursor export sets `hooks` to an empty Cursor-native stub under
`.cursor-plugin/` so Cursor does not parse the Claude hooks file as a plugin hook
config ([component discovery](https://cursor.com/docs/reference/plugins) — specifying
`hooks` replaces default `hooks/hooks.json` discovery). Skills, agents, and rules still load.
Export package: [`scripts/cursor-export/`](scripts/cursor-export/README.md).

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
  `node scripts/generate-cursor-manifests.mjs` — implementation in
  [`scripts/cursor-export/`](scripts/cursor-export/README.md)).
- `plugins/` — one directory per plugin (`plugins/<name>/.claude-plugin/plugin.json` and
  `.mcp.json` / `hooks/hooks.json` are Claude SSOTs; Cursor
  `plugins/<name>/.cursor-plugin/**` and ported `mcp.json` are generated).
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
