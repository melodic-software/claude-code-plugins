# Melodic Software Claude Code plugins

A public [Claude Code](https://code.claude.com/docs) plugin marketplace of reusable, repo-agnostic
skills, hooks, and agents. Each plugin works in any repository, and consumers customize it without
editing the plugin itself.

## Use this marketplace

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install <plugin-name>@melodic-software
```

Browse and manage plugins with `/plugin`. To refresh after updates, run
`/plugin marketplace update melodic-software`.

An install from GitHub is a copy keyed on the plugin's `version`, so a change reaches it only when a
release raises that version. A marketplace added from a local clone loads each plugin in place, so
edits apply at the next session or `/reload-plugins`. See "Same-version commit drift" in
[`docs/migration-playbook.md`](docs/migration-playbook.md#same-version-commit-drift-copied-installs).

A plugin whose catalog entry sets `defaultEnabled: false` installs disabled. Enable it with
`/plugin enable <plugin-name>`.

### Enable plugin suggestions for an organization

Some catalog entries declare `relevance` signals, so Claude Code can suggest the plugin when a
session's work matches. Suggestions appear only after an administrator allowlists the marketplace in
managed settings. This block declares the marketplace source and allowlists it:

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

The rules for this block are in
[Recommend plugins for your org](https://code.claude.com/docs/en/plugins/relevance).

## Find a plugin or skill

- [Skill cheat sheet](docs/skill-cheat-sheet.md): from what you are doing to the skill that does it.
- [Plugin catalog](docs/catalog.md): every plugin by category, generated from the manifests.
- [Catalog taxonomy](docs/catalog-taxonomy.md): the categories the catalog uses.

## What this marketplace publishes

This repository is the only authoritative listing of what this marketplace publishes: the plugins in
`plugins/` on the default branch, listed machine-readably in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

Some third-party directory sites credit this publisher with skills that have never existed here. If
a skill credited to this marketplace is not in `plugins/` on the default branch, it is not ours.
Install from the source above, not from a mirror or directory listing. This repository does not
maintain entries on third-party lists such as
[awesome-ai-plugins](https://github.com/hashgraph-online/awesome-ai-plugins) and declines requests
to add them.

## Contributing

| Path | Holds |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Operating rules for agents working in this repository (`CLAUDE.md` imports it) |
| [`docs/migration-playbook.md`](docs/migration-playbook.md) | Design charter, extensibility model, the per-plugin migration gate, and the local development loop |
| [`scripts/README.md`](scripts/README.md) | Validating a change before you push: affected tests, local forms of CI gates, the check-script contract |
| [`REVIEW.md`](REVIEW.md) and [`docs/review/`](docs/review/README.md) | Review criteria |
| [`docs/official-docs.md`](docs/official-docs.md) | Where to find the official Claude Code docs, and how to cite them |
| `lib/` | The shared shell helpers. `scripts/sync-<helper>.sh` copies each into the plugins that use it, and CI rejects a copy that differs, so edit `lib/`, never a copy |
| `prompts/` | Launch-prompt templates to fill in and paste into a session |
| `.claude/` | This repository's own Claude Code configuration; it ships to no one |
| `.github/` | Workflows and the policy files they read |

## License

[MIT](LICENSE).
