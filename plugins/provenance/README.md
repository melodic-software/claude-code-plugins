# provenance (deprecated)

This plugin was renamed to `attribution`. Everything it did now lives in
`attribution@melodic-software`: `/provenance:audit` is `/attribution:audit` and
`/provenance:setup` is `/attribution:setup`.

This entry is a one-release shim. Its two skills only tell you where the real skill went; they
do no work. It is removed in a later release.

## Migrate

1. Install the renamed plugin: `/plugin install attribution@melodic-software`.
2. Remove `provenance@melodic-software` from `enabledPlugins` in your settings, or uninstall it
   with `/plugin uninstall provenance@melodic-software`.
3. Rename a repository's `.claude/provenance.json` to `.claude/attribution.json` (and
   `.claude/provenance.local.json` to `.claude/attribution.local.json`, and
   `~/.claude/provenance.json` to `~/.claude/attribution.json`). The renamed plugin does not read
   the old file names.

See the [attribution README](../attribution/README.md) for what the plugin does. The restated
frontmatter-fact detector from #3525 lives there, as `detect-restated-facts.sh` under
`/attribution:audit`.
